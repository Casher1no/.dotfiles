# Dotfiles — Neovim config

## Requirements

- Neovim ≥ 0.11
- Git
- A Nerd Font (e.g. JetBrainsMono Nerd Font) set in your terminal
- ripgrep (`rg`) — for Telescope live grep
- Node.js — for several LSP servers
- (Optional, per language) JDK 21 (Java), .NET SDK (C#), PHP + Xdebug

## Mac setup

- Install tools: `brew install neovim git ripgrep node`
- Clone this repo: `git clone <repo-url> ~/.dotfiles`
- Symlink the config: `ln -s ~/.dotfiles/nvim ~/.config/nvim`
- Launch `nvim` — plugins and LSP/DAP tools install automatically on first run

## Windows setup

- Install tools: `winget install Neovim.Neovim Git.Git BurntSushi.ripgrep.MSVC OpenJS.NodeJS`
- Clone this repo: `git clone <repo-url> $HOME\.dotfiles`
- Symlink the config (run PowerShell as Administrator):
  `New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$HOME\.dotfiles\nvim"`
- Launch `nvim` — plugins and LSP/DAP tools install automatically on first run
