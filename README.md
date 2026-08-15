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
