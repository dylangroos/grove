#!/usr/bin/env bash
# Remote installer for grove — downloads from GitHub and installs to ~/.local/bin
set -euo pipefail

REPO="dylangroos/grove"
BRANCH="main"
INSTALL_DIR="$HOME/.local/bin"
GROVE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/grove"

echo "Installing grove..."

mkdir -p "$INSTALL_DIR"

# Remove any existing file/symlink — stale symlinks from manual installs
# cause curl -o to follow the dead link and write to the wrong place
rm -f "$INSTALL_DIR/grove"

curl -fsSL "$GROVE_URL" -o "$INSTALL_DIR/grove"
chmod +x "$INSTALL_DIR/grove"

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

# Shell completions
COMPLETION_LINE='eval "$(gr completions)"'
if ! grep -qF 'gr completions' "$PROFILE" 2>/dev/null; then
    echo "" >> "$PROFILE"
    echo "# grove shell completions" >> "$PROFILE"
    echo "$COMPLETION_LINE" >> "$PROFILE"
fi

echo "grove installed — open a new terminal to start using it"
