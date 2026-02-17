#!/usr/bin/env bash
# Remote installer for grove — downloads from GitHub and installs to ~/.local/bin
set -euo pipefail

REPO="dylangroos/grove"
BRANCH="main"
INSTALL_DIR="$HOME/.local/bin"
GROVE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/grove"

echo "Installing grove..."

mkdir -p "$INSTALL_DIR"
curl -fsSL "$GROVE_URL" -o "$INSTALL_DIR/grove"
chmod +x "$INSTALL_DIR/grove"

echo "grove installed → $INSTALL_DIR/grove"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    SHELL_NAME="$(basename "$SHELL")"
    case "$SHELL_NAME" in
        zsh)  PROFILE="$HOME/.zshrc" ;;
        bash) PROFILE="$HOME/.bashrc" ;;
        *)    PROFILE="$HOME/.profile" ;;
    esac

    EXPORT_LINE='export PATH="$HOME/.local/bin:$PATH"'

    if ! grep -qF '.local/bin' "$PROFILE" 2>/dev/null; then
        echo "" >> "$PROFILE"
        echo "$EXPORT_LINE" >> "$PROFILE"
        echo "Added $INSTALL_DIR to PATH in $PROFILE"
        echo "Restart your shell or run:  source $PROFILE"
    fi
fi
