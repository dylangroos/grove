#!/usr/bin/env bash
# Install grove CLI by symlinking to ~/.local/bin/grove
set -euo pipefail

GROVE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/grove"
INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"
ln -sf "$GROVE_SCRIPT" "$INSTALL_DIR/grove"

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
    fi

    export PATH="$INSTALL_DIR:$PATH"
fi
