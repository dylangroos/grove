#!/usr/bin/env bash
# Install grove CLI by symlinking to ~/.local/bin/grove
set -euo pipefail

GROVE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/grove"
INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"
ln -sf "$GROVE_SCRIPT" "$INSTALL_DIR/grove"

echo "grove installed → $INSTALL_DIR/grove"

# Check if ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "NOTE: $INSTALL_DIR is not in your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
