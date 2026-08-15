#!/usr/bin/env bash
# Fresh-machine setup for this dotfiles repo. Idempotent — safe to re-run.
# Does only what can't happen inside nvim (system packages + the config
# symlink), then hands over to `nvim --headless "+Doctor sync"`, which
# installs plugins, treesitter parsers and mason servers from the same
# dependency registry the in-editor Doctor panel uses.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
# llvm carries clangd + clang-format for the C/C++ layer
CORE_TOOLS=(neovim git ripgrep fd node llvm)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }

# ── system packages ─────────────────────────────────────────────────────
case "$(uname -s)" in
Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
        say "Installing Xcode Command Line Tools (needed for git + compiling parsers)…"
        xcode-select --install || true
        warn "finish the CLT installer, then re-run this script"
        exit 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found — install it first:"
        warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    say "brew install ${CORE_TOOLS[*]}"
    brew install "${CORE_TOOLS[@]}" || warn "brew reported errors — Doctor will show what's still missing"
    ;;
Linux)
    if command -v apt-get >/dev/null 2>&1; then
        say "apt-get install core tools (needs sudo)"
        sudo apt-get update || warn "apt-get update reported errors — continuing"
        # fd is fd-find on debian/ubuntu; neovim from apt may be old — Doctor flags < 0.12
        sudo apt-get install -y neovim git ripgrep fd-find nodejs npm build-essential clangd curl unzip ||
            warn "apt reported errors — Doctor will show what's still missing"
    elif command -v dnf >/dev/null 2>&1; then
        say "dnf install core tools (needs sudo)"
        sudo dnf install -y neovim git ripgrep fd-find nodejs npm gcc gcc-c++ clang-tools-extra curl unzip ||
            warn "dnf reported errors — Doctor will show what's still missing"
    elif command -v pacman >/dev/null 2>&1; then
        say "pacman install core tools (needs sudo)"
        sudo pacman -S --noconfirm --needed neovim git ripgrep fd nodejs npm base-devel clang curl unzip ||
            warn "pacman reported errors — Doctor will show what's still missing"
    else
        warn "no supported package manager found — install manually: ${CORE_TOOLS[*]}"
    fi
    ;;
*)
    warn "unsupported OS $(uname -s) — install manually: ${CORE_TOOLS[*]}"
    ;;
esac

# ── config symlink ───────────────────────────────────────────────────────
mkdir -p "$(dirname "$CONFIG_DIR")"
if [ -e "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ]; then
    if [ "$(readlink "$CONFIG_DIR" 2>/dev/null || true)" = "$REPO/nvim" ]; then
        say "symlink already in place: $CONFIG_DIR → $REPO/nvim"
    else
        BACKUP="$CONFIG_DIR.backup.$(date +%s)"
        say "existing $CONFIG_DIR moved to $BACKUP"
        mv "$CONFIG_DIR" "$BACKUP"
        ln -s "$REPO/nvim" "$CONFIG_DIR"
    fi
else
    say "linking $CONFIG_DIR → $REPO/nvim"
    ln -s "$REPO/nvim" "$CONFIG_DIR"
fi

# ── editor layer (plugins, parsers, LSP servers) ────────────────────────
if command -v nvim >/dev/null 2>&1; then
    say "running nvim --headless '+Doctor sync' (first run also bootstraps lazy.nvim — this can take a few minutes)…"
    nvim --headless "+Doctor sync" "+qa" || warn "Doctor sync reported problems — open nvim and check the Doctor panel"
else
    warn "nvim not on PATH — install it, then run: nvim --headless '+Doctor sync'"
fi

say "done. Open nvim and press <leader><space> → Doctor to see the full status."
