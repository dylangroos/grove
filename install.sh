#!/usr/bin/env bash
# Install grove — works both locally (git clone) and remotely (curl | bash)
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"

# Remove any existing file/symlink to avoid stale symlink issues
rm -f "$INSTALL_DIR/grove"

# If running from a local clone, symlink. Otherwise, download.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/grove" ]]; then
    ln -sf "$SCRIPT_DIR/grove" "$INSTALL_DIR/grove"
else
    curl -fsSL "https://raw.githubusercontent.com/dylangroos/grove/main/grove" \
        -o "$INSTALL_DIR/grove"
    chmod +x "$INSTALL_DIR/grove"
fi

# Ensure ~/.local/bin is in PATH
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
fi

echo "grove installed — open a new terminal to start using it"
