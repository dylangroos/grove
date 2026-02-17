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

# Check if ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "NOTE: $INSTALL_DIR is not in your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
