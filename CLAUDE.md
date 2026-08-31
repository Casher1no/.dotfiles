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
- **Normalising is for comparing, not for writing.** When you write a path
  *into a file another tool owns*, echo back the separator that file already
  uses rather than the one `vim.fs.normalize` gave you. Unity's
  `Assembly-CSharp.csproj` lists `Assets\Scripts\Foo.cs` on Windows; writing
  `Assets/Scripts/Foo.cs` alongside it means the duplicate check never
  matches and the file ends up listed twice (the SDK then fails with
  NETSDK1022). `util/unity_sync.lua` detects the separator per file
  (`_detect_sep`) and the line ending too (`_detect_nl`) — a CRLF file
  spliced with `\n` shows up in git as rewritten end to end.

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
- **Hashing has no common spelling.** macOS ships `shasum` but not
  `sha256sum`, Linux ships `sha256sum`, Windows ships neither and answers
  with `certutil -hashfile <f> SHA256` — whose output format differs again
  (a header line, the hash, a status line; older builds space the hex out
  byte-wise). `util/deps_lsp.lua` splits this into `sha256_cmd()` (returns
  an argv, testable on one machine) and one `parse_sha256()` that copes with
  all three formats. And `vim.fn.sha256()` is not the way out: Vim strings
  cannot carry the NUL bytes of a gzip archive intact, so hashing a
  downloaded binary through it silently returns the wrong digest.
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
(revealing a file in the file manager, recursive copy, recursive delete).
Put new ones there
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
   copy. Where a module reads `vim.fn.has("win32")` once at load time,
   `load_as()` is just: clear `package.loaded`, swap `vim.fn` for a table
   whose `has` lies, `require` the real file, put `vim.fn` back.

   Beware plugin lifecycles when testing through one. `require("neo-tree")`
   does *not* run neo-tree's setup — its `setup()` only stashes the config,
   and `opts.event_handlers` are not subscribed until the tree is first
   used. Firing `neo-tree.events` at it before then silently reaches
   nobody, which reads as a broken handler. Drive it the way a user would
   (`:Neotree close` is enough) before asserting.
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

## Traps that already bit us

Not platform-specific, but the same shape of problem: an API that accepts
what you give it and then quietly does something else.

- **`textDocument/references` on a method that implements an interface
  answers for the whole family.** tsserver returns every implementation of
  it, in your code and in `node_modules`; angularls then maps each of those
  to the template usages of *that* class. `gd` on a pipe's `transform()`
  came back with 279 + 67 hits — 184 of them `| transloco` — one of which
  was the pipe being asked about. The server is not wrong; the request is
  ambiguous. `util/angular.lua` narrows it back to the one spelling that
  can mean this class (`| <the @Pipe name>`), and the picker title names the
  pipe so the narrowing is visible. Anything similar needs the same shape:
  attribute the hits yourself, and say in the UI that you did.

- **`vim.fs.normalize` only rewrites `\` on Windows.** So a helper that
  canonicalises for comparison must fold backslashes itself if it is ever
  fed a path produced on another machine's convention — or, as here, if the
  test suite wants to exercise the Windows arm from macOS. `load_as()` can
  lie about `vim.fn.has("win32")`, but it cannot make `vim.fs.normalize`
  behave like Windows; `util/tree_tints.lua` folds separators first for
  exactly that reason. It also short-circuits plain absolute paths before
  calling `normalize` at all: `classify()` runs per visible row on every
  picker keystroke, and `normalize` costs ~5 µs a call (2.6 µs/call with
  the short-circuit vs 0.8 µs for the old raw prefix compare — 0.13 ms for
  a 50-row redraw).

- **A server offering inlay hints or code lenses does not mean either
  renders.** The client has to switch each on per buffer
  (`vim.lsp.inlay_hint.enable(true, { bufnr })`,
  `vim.lsp.codelens.enable(true, { bufnr })`) and nothing in this config did
  until `lua/lsp/deps_lsp.lua` — so a server whose entire output is hints
  attaches cleanly, reports healthy in `:checkhealth lsp`, and shows
  absolutely nothing. Enable it in that server's own config's `on_attach`.
  Use `codelens.enable`, not `codelens.refresh` — refresh is deprecated in
  0.12 and removed in 0.13, and `enable` goes through `vim.lsp._capability`,
  which owns the re-request on change, so a hand-rolled
  `BufEnter`/`TextChanged` autocmd only duplicates it.

- **deps-lsp's code-action list disagrees with its own diagnostics.** The
  diagnostic and the inlay hint resolve "latest" through deps-core's
  `find_latest_stable`; the code actions come from
  `prepare_version_display_items`, which takes the five newest entries off
  the raw registry listing and never calls it. On any package that publishes
  prereleases to its registry, that means the ★ default action writes one:
  on `react` the hint says `↑ 19.2.8` while the action list offers five
  canary builds (`19.3.0-canary-…`), and on `typescript`, `7.1.0-dev.…`
  against a hint of `7.0.2`. Applying the default there pins a canary.
  It cannot be narrowed client-side the way `util/angular.lua` narrows
  tsserver's references — for those packages *all five* offered versions are
  prereleases, so the stable one is never in the response to pick. Trust the
  hint, not the action list, for anything publishing canaries; everything
  with a normal release cadence (express, lodash, the composer packages) is
  correct. Upstream: `crates/deps-core/src/completion.rs`,
  `prepare_version_display_items`.

- **neo-tree's delete is permanent, and `u` never undid it.** `d` on a row
  unlinks the file (shelling out to `rm -Rf` on unix, `rmdir /s /q` on
  Windows), so a mis-aimed keypress was unrecoverable. The hook that fixes
  this is `before_file_delete`: it fires *after* neo-tree's confirm prompt
  and *before* the unlink, and a handler returning `{ handled = true }` makes
  neo-tree skip its own delete while still calling `complete()` — so
  `file_deleted` still fires and `util/unity_sync` still takes the script out
  of the csproj. `util/file_trash.lua` moves the file to
  `stdpath("state")/trash` there instead, and `u` / `<C-z>` in the tree
  restore it. Two things that bite here: the manifest has to be on disk, not
  in memory, or the undo dies with the session (noticing tomorrow is the case
  it is for); and `fs_rename` fails with EXDEV whenever the trash and the
  project are on different volumes, which is the *normal* case (`F:\Projects`
  vs `C:\Users\…\state`, or a mac project on an external disk) — the
  copy-then-delete fallback is the arm that actually runs there, so test it
  by stubbing `fs_rename` to fail rather than assuming rename covers it.

- **`'autowriteall'` does not cover `:bdelete`/`:bwipeout`,** despite covering
  every other way of leaving a buffer behind, and it stops to ask about a file
  that changed on disk. `util/autosave.lua` covers both — `CmdlineLeave` for
  the former (Neovim checks the buffer itself, before any autocommand of its
  own would run) and `update!` for the latter.

- **A plugin's README is not its source, and both stay quiet when they
  disagree.** jiaoshijie/undotree documents its diff buffer's filetype as
  `undotreeDiff`; `runtime.lua:172` sets `UndotreeDiff`. An
  `ignore_filetype` list copied from the README therefore matches nothing
  and reports nothing — the guard is present, spelled plausibly, and dead.
  The same spec has two more knobs that read as configured and do nothing:
  `layout` and `window.height` are only consulted on the non-float path
  (`ui.lua:30,32`), so with `float_diff = true` they are inert. Neither
  errors, neither warns. When a plugin option is a *name* it must match
  (a filetype, an event, a highlight group), read the line in the plugin
  that consumes it rather than the line in its README that describes it,
  and assert it from a test — `plugins/undotree.lua` carries the source
  line numbers in a comment for exactly this reason.

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
