# Working on this repo

This config is used daily on **Windows, macOS and Linux** — `bootstrap.ps1`
and `bootstrap.sh` both exist and both are supported. Treat all three as
first-class.

## The rule

**A feature is not done until it works on Windows, macOS and Linux.**

Not "works on my machine and probably degrades gracefully elsewhere". A
feature that silently does nothing on one OS is worse than one that isn't
written yet, because nothing reports it — you just quietly lose the feature
and don't find out for months.

When a capability genuinely can't exist on some platform, say so **in code**:
guard it, and make the guard visible (a `vim.notify`, a Doctor entry, a
comment saying why). Never let it fail silently.

## Paths

This is where it actually goes wrong. Windows uses `\`, and the APIs disagree
with each other about it:

- `vim.api.nvim_buf_get_name()`, `vim.fn.getcwd()`, `vim.fn.expand("%")` →
  **backslashes** on Windows.
- `vim.fs.normalize()` → always **forward slashes**, on every OS.
- Third-party plugins pick their own. neo-tree normalizes to *backslashes*
  (`neo-tree.utils.normalize_path`); most others use forward slashes.

Rules that follow:

- **Never compare, prefix-match or split raw paths.** Run both sides through
  `vim.fs.normalize()` first, then you may assume `/`.
- **Never hand-build a path with `..`.** Use `vim.fs.joinpath()`.
- **Never test for absoluteness with `path:sub(1, 1) == "/"`.** That is false
  for every Windows path. See `util/telescope_preview_title.lua:31` for the
  form that handles both (`^%a:[/\\]` covers `F:\` and `F:/`).
- **Case-fold before comparing on Windows.** NTFS is case-insensitive, so
  `F:\Projects` and `f:\projects` are the same directory and must compare
  equal. `util/mru.lua` and `util/focus_tree.lua` both do this.

`util/focus_tree.lua` has the canonical helper — copy that shape:

```lua
local is_win = vim.fn.has("win32") == 1

local function canon(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    path = vim.fs.normalize(path):gsub("/+$", "")
    return is_win and path:lower() or path
end
```

When prefix-matching a directory, always compare against `root .. "/"`, not
`root` — otherwise `.../The Inheritance Extra` counts as inside
`.../The Inheritance`.

## Shelling out

Assume **nothing** exists. Windows has no `sh`, `xargs`, `stat`, `cp`, `mv`,
`open`, `which`, `sed` or `awk`; macOS `stat` takes `-f`, GNU `stat` takes
`-c`; Linux has no `open`.

- Guard every external tool with `vim.fn.executable(...) == 1` and provide a
  fallback or a clear message. `plugins/telescope.lua` (rg → fd → fdfind →
  telescope's own fallback) and `util/cpp.lua` are the pattern.
- Prefer a Neovim/libuv API over a subprocess whenever one exists:
  `vim.ui.open` instead of `open`/`xdg-open`, `vim.uv.fs_*` instead of
  `stat`/`cp`, `vim.fs.find`/`vim.fs.dir` instead of `find`.
- If you must branch per-OS, branch on all three and implement all three.
  `util/clangd_config.lua` and `plugins/treesitter.lua` do this properly —
  treesitter's `ensure_parser_toolchain()` is a good example of solving a
  Windows-only problem without breaking the others.
- `vim.system({...})` takes an argv list — good, it avoids quoting entirely.
  Keep it that way; don't drop back to a shell string.

## Filesystem semantics

- **Case sensitivity**: Windows/macOS are usually insensitive, Linux is
  sensitive. Code that only ever runs on one will break on another.
- **Executables**: `.exe` suffix on Windows. See `util/cpp.lua:28`.
- **Path length / spaces**: project paths here contain spaces
  (`F:\Projects\The Inheritance`). Always `vim.fn.fnameescape()` for Ex
  commands, and pass argv lists to `vim.system`.
- **Line endings**: this repo is checked out CRLF on Windows. Don't write
  code that depends on `\n`-only files.

## Where OS-specific code goes

`util/os_files.lua` — anything the three platforms spell differently
(revealing a file in the file manager, recursive copy). Put new ones there
rather than inline in a plugin spec: a `local` inside a spec table cannot be
required, so it cannot be tested, and untestable is how the last round of
these stayed broken for months.

Keep the platform *decision* and the platform *action* separate, so the
decision can be tested without performing the action. `reveal_cmd()` returns
an argv and `reveal()` spawns it — that split is what let all three arms get
test coverage from one machine.

## Before you call it done

For anything touching paths, the filesystem, or an external process:

1. **State which OSes you actually ran it on** and which you reasoned about.
   Don't blur the two. If a platform can't be tested from here, name it and
   name the specific assumption left unverified.
2. **Make it testable.** If verifying it means requiring a module, move it
   into one. Loading the real source with `vim.fn` stubbed exercises the
   other platforms' branches for real — see
   `reveal_cmd` and the `load_as()` harness pattern. That beats reasoning,
   and it beats copying the logic into the test, which only ever tests the
   copy.
3. **Test multiple scenarios, not the happy path.** For this codebase that
   means at minimum: both separator styles, mixed case, names with spaces
   and non-ASCII, a path outside the project root, a sibling directory whose
   name is a *prefix* of the root, an empty string, a missing source, and
   whatever batch/chunk boundary the API has (`fs_readdir` reads 64 entries
   at a time — the bug only appears at 65).
4. **Check performance, with a number.** Say what it costs and how often it
   runs; "feels fine" is not a measurement. Anything on the main loop, in a
   sorter, or on a per-keystroke path needs a figure before and after:
   ```sh
   nvim --headless -c "luafile test.lua" -c "qa!"
   ```
   Where you replaced something, measure the thing you replaced too — the
   libuv copy turned out to beat `cp -R` (164ms vs 271ms for 400 files), and
   that is worth knowing rather than assuming.
5. **Update this file** in the same change. New helper, changed rule, gap
   closed, gap discovered — it goes in here, not just in a commit message.
   The section below is only useful if it is true.

## Known cross-platform gaps

None currently open. Last swept after the `util/os_files.lua` change; the
sweep is:

```sh
# unix-only binaries invoked directly
grep -rnE '"(open|cp|mv|rm|sh|xargs|stat|chmod|which|sed|awk)"' --include=*.lua lua/
# separator assumptions that are false on Windows
grep -rnE 'sub\(1, ?1\) ?== ?"/"' --include=*.lua lua/
```

Read the hits; the first grep matches any string literal, not just spawns.
As of the last sweep the only hits are a neo-tree *command* name
(`["<right>"] = "open"`), the guarded macOS branch in `util/os_files.lua`,
and `"sh"` in `search_rank.lua`'s file-extension list — none of them invoke
anything. The second grep should only ever hit the combined absolute test.
Anything else is a real gap.

For the record, these were the three that had been silently dead and are now
fixed — the shape of each is worth recognising:

- `open -R` for "reveal in Finder" — macOS-only command, no guard, no
  fallback. Now `util/os_files.reveal`.
- `cp -R` for the drag-and-drop copy — no `cp` on Windows. Now
  `util/os_files.copy`, via libuv.
- `util/lsp_refresh.lua`'s watch bridge — dead *twice*: an `IS_WINDOWS`
  early return, and `root:sub(1, 1) == "/"` rejecting every `F:\...` root.
  Now `git ls-files` + libuv stat, one code path for all three.
