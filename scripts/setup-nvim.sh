#!/usr/bin/env bash
set -e

# -------------------------
# Install Chocolatey (if not installed)
# -------------------------
if ! command -v choco &> /dev/null; then
    echo "➡ Installing Chocolatey..."
    powershell -NoProfile -ExecutionPolicy Bypass -Command \
        "Set-ExecutionPolicy Bypass -Scope Process; \
         [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; \
         iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
else
    echo "✔ Chocolatey already installed, skipping..."
fi

echo "=== Neovim Setup Script for Windows ==="

# -------------------------
# 1. Install dependencies
# -------------------------
if ! command -v winget &> /dev/null; then
    echo "❌ winget not found. Please install it from Microsoft Store."
    exit 1
fi

if ! command -v nvim &> /dev/null; then
    echo "➡ Installing Neovim..."
    winget install -e --id Neovim.Neovim -h
else
    echo "✔ Neovim already installed, skipping..."
fi

if ! command -v git &> /dev/null; then
    echo "➡ Installing Git..."
    winget install -e --id Git.Git -h
else
    echo "✔ Git already installed, skipping..."
fi

if ! command -v lazygit &> /dev/null; then
    echo "➡ Installing Lazygit..."
    winget install -e --id JesseDuffield.lazygit -h
else
    echo "✔ Lazygit already installed, skipping..."
fi

if ! ls /c/Windows/Fonts | grep -qi "Hurmit"; then
    echo "➡ Installing Hurmit Nerd Font..."
    winget install -e --id NerdFonts.Hurmit -h
else
    echo "✔ Hurmit Nerd Font already installed, skipping..."
fi

if ! command -v fd &> /dev/null; then
    echo "➡ Installing fd (optional, improves file search)..."
    cmd //c "winget install -e --id fd-find.fd -h || echo '⚠ fd install failed'"
else
    echo "✔ fd already installed, skipping..."
fi

# -------------------------
# 2. Detect paths
# -------------------------
CONFIG_TARGET="$HOME/AppData/Local/nvim"

if [ -d "$PWD/nvim" ]; then
    DOTFILES_NVIM="$PWD/nvim"
    echo "➡ Using current folder: $DOTFILES_NVIM"
else
    DOTFILES_NVIM=$(find /c -type d -path "*/.dotfiles/nvim" 2>/dev/null | head -n 1)
    if [ -z "$DOTFILES_NVIM" ]; then
        echo "❌ Could not find '.dotfiles/nvim'!"
        exit 1
    fi
    echo "➡ Found dotfiles: $DOTFILES_NVIM"
fi

# -------------------------
# 3. Backup old config
# -------------------------
if [ -d "$CONFIG_TARGET" ] || [ -L "$CONFIG_TARGET" ]; then
    echo "⚠ Found existing config, backing up..."
    mv "$CONFIG_TARGET" "${CONFIG_TARGET}.backup.$(date +%s)"
fi

# -------------------------
# 4. Create symlink
# -------------------------
create_symlink() {
    local source="$1"
    local target="$2"

    # Check if WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "➡ WSL detected → using ln -s"
        ln -s "$source" "$target"
    else
        echo "➡ Git Bash / Windows detected → using mklink"
        cmd //c "mklink /D $(cygpath -w "$target") $(cygpath -w "$source")"
    fi
}

echo "➡ Linking $DOTFILES_NVIM → $CONFIG_TARGET"
create_symlink "$DOTFILES_NVIM" "$CONFIG_TARGET"

# -------------------------
# 5. Done
# -------------------------
echo ""
echo "=== ✅ Neovim setup complete! Run 'nvim' to start ==="
echo ""
read -p "Press Enter to close..."