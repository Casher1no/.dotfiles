#!/usr/bin/env bash
set -e

echo "=== Neovim Setup Script ==="

# -------------------------
# 1. Detect OS
# -------------------------
OS_TYPE="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
        OS_TYPE="wsl"
    else
        OS_TYPE="linux"
    fi
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* || "$OSTYPE" == "win32" ]]; then
    OS_TYPE="windows"
fi

echo "➡ Detected OS: $OS_TYPE"

# -------------------------
# 2. Install dependencies
# -------------------------
install_windows() {
    if ! command -v winget &> /dev/null; then
        echo "❌ winget not found. Please install it from Microsoft Store."
        exit 1
    fi

    for pkg in "Neovim.Neovim" "Git.Git" "JesseDuffield.lazygit" "NerdFonts.Hurmit"; do
        cmd_name=$(echo $pkg | awk -F. '{print $2}' | tr '[:upper:]' '[:lower:]')
        if ! command -v $cmd_name &> /dev/null && [ "$pkg" != "NerdFonts.Hurmit" ]; then
            echo "➡ Installing $cmd_name..."
            winget install -e --id $pkg -h
        elif [ "$pkg" == "NerdFonts.Hurmit" ]; then
            fc-list | grep -qi "Hurmit Nerd Font" || winget install -e --id $pkg -h
        else
            echo "✔ $cmd_name already installed, skipping..."
        fi
    done
}

install_linux() {
    echo "➡ Updating package list..."
    sudo apt update
    for pkg in neovim git lazygit; do
        if ! command -v $pkg &> /dev/null; then
            echo "➡ Installing $pkg..."
            sudo apt install -y $pkg
        else
            echo "✔ $pkg already installed, skipping..."
        fi
    done
}

if [ "$OS_TYPE" == "windows" ]; then
    install_windows
elif [ "$OS_TYPE" == "linux" ] || [ "$OS_TYPE" == "wsl" ]; then
    install_linux
fi

# -------------------------
# 3. Detect paths
# -------------------------
CONFIG_TARGET="$HOME/AppData/Local/nvim"
[ "$OS_TYPE" == "linux" ] && CONFIG_TARGET="$HOME/.config/nvim"

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
# 4. Backup old config
# -------------------------
if [ -d "$CONFIG_TARGET" ] || [ -L "$CONFIG_TARGET" ]; then
    echo "⚠ Found existing config, backing up..."
    mv "$CONFIG_TARGET" "${CONFIG_TARGET}.backup.$(date +%s)"
fi

# -------------------------
# 5. Create symlink
# -------------------------
create_symlink() {
    local source="$1"
    local target="$2"

    if [ "$OS_TYPE" == "windows" ]; then
        echo "➡ Creating Windows symlink..."
        cmd //c "mklink /D $(cygpath -w "$target") $(cygpath -w "$source")"
    else
        echo "➡ Creating Linux symlink..."
        ln -s "$source" "$target"
    fi
}

echo "➡ Linking $DOTFILES_NVIM → $CONFIG_TARGET"
create_symlink "$DOTFILES_NVIM" "$CONFIG_TARGET"

# -------------------------
# 6. Done
# -------------------------
echo ""
echo "=== ✅ Neovim setup complete! Run 'nvim' to start ==="
[ "$OS_TYPE" == "windows" ] && read -p "Press Enter to close..."
