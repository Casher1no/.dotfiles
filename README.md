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

## Windows setup

- Install tools: `winget install Neovim.Neovim Git.Git BurntSushi.ripgrep.MSVC OpenJS.NodeJS`
- Clone this repo: `git clone <repo-url> $HOME\.dotfiles`
- Symlink the config (run PowerShell as Administrator):
  `New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$HOME\.dotfiles\nvim"`
- Run `nvim --headless "+Doctor sync"`, or just launch `nvim` and open the
  Doctor panel.
