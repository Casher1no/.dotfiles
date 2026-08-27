# Dotfiles — Neovim config

## Setup (macOS / Linux)

```sh
git clone <repo-url> ~/Projects/.dotfiles
~/Projects/.dotfiles/bootstrap.sh
```

That's it. `bootstrap.sh` installs the core tools (Homebrew/apt), symlinks
`~/.config/nvim` into the repo, and runs `nvim --headless "+Doctor sync"`,
which installs the plugins (pinned by `lazy-lock.json`), the treesitter
parsers and every LSP/DAP server via mason.

Set a **Nerd Font** in your terminal (e.g. JetBrainsMono Nerd Font) — the
one thing a script can't do for you.

## Doctor

The config knows its own dependencies (`nvim/lua/util/doctor/registry.lua`)
and can check, install and update them:

- `<leader><space>` → **Doctor** — live status panel in the command palette:
  ✓ installed, ✗ missing, ↑ update available. `⏎` on a row installs that
  dependency; bottom actions install everything missing, check brew/mason
  for updates, or update everything outdated.
- `:Doctor` — opens the same panel. `:Doctor report | sync | install |
  update | log` for the non-interactive flavors.
- `:checkhealth doctor` — the same probes through nvim's health UI.

Optional per-language stacks (PHP, Python, JDK 21, .NET SDK) show as
warnings, not errors, until you install them.

## Setup (Windows)

In an **elevated** PowerShell:

```powershell
git clone <repo-url> $HOME\Projects\.dotfiles
Set-ExecutionPolicy Bypass -Scope Process -Force
& $HOME\Projects\.dotfiles\bootstrap.ps1
```

`bootstrap.ps1` installs Chocolatey (if needed) and the core tools
(`neovim git ripgrep fd nodejs-lts mingw llvm`), links `%LOCALAPPDATA%\nvim`
into the repo, and runs the same `Doctor sync`. The in-editor Doctor
installs system packages through choco on Windows and apt/dnf/pacman on
Linux (elevated installs open in a terminal split so sudo/UAC output is
visible).

## Unity as an external editor (Windows)

Double-clicking a script in Unity can open it in Neovim at the right line.
This is **entirely a Unity setting** — nothing in this repo, no launcher
script. In Unity: **Edit → Preferences → External Tools → External Script
Editor → Browse…**. Picking an executable Unity doesn't recognise makes it
show an **External Script Editor Args** field, which substitutes
`$(File)`, `$(Line)`, `$(Column)` and `$(ProjectPath)`.

Point it at Windows Terminal:

| Field | Value |
| --- | --- |
| External Script Editor | `C:\Users\<you>\AppData\Local\Microsoft\WindowsApps\wt.exe` |
| External Script Editor Args | `-d "$(ProjectPath)" nvim "+$(Line)" "$(File)"` |

Or keep `powershell.exe` as the editor and let it call through:

```
-NoProfile -WindowStyle Hidden -Command "wt -d '$(ProjectPath)' nvim '+$(Line)' '$(File)'"
```

Neovim needs a real console, which is why the target is a terminal rather
than `nvim.exe` — pointed straight at `nvim.exe` it gets no TTY and exits
immediately.

Notes:

- Set this in the Preferences UI, not the registry. Unity caches the values
  (`kScriptsDefaultApp` / `kScriptEditorArgs` under
  `HKCU:\Software\Unity Technologies\Unity Editor 5.x`) and rewrites them on
  exit, so a registry edit made while the Editor is running is lost.
- `/c` is **cmd.exe** syntax, not PowerShell. `powershell.exe /c script.bat`
  silently does nothing.
- Every double-click starts a **new** Neovim. Reusing an instance you already
  have open needs `nvim --server <address> --remote-expr`, and the address has
  to be predictable — Neovim's default (`\\.\pipe\nvim.<pid>.0`) is not — so
  that would need config on the Neovim side, not just this setting.
- Unity only regenerates `Assembly-CSharp.csproj` when an IDE package
  (`com.unity.ide.rider` / `.visualstudio`) recognises the selected editor.
  With a custom one it may stop, which leaves Roslyn blind to new scripts —
  `:Usync` (see `nvim/lua/util/unity_sync.lua`) rewrites the `<Compile>` list
  from disk when that happens.
