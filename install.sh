#!/usr/bin/env bash
# Install grove — works both locally (git clone) and remotely (curl | bash)
set -euo pipefail

# ─── Install dtach if missing ────────────────────────────────────────────────

if ! command -v dtach >/dev/null 2>&1; then
    # Determine install command
    DTACH_CMD=""
    if command -v apt-get >/dev/null 2>&1; then
        DTACH_CMD="sudo apt-get update -qq && sudo apt-get install -y -qq dtach"
    elif command -v brew >/dev/null 2>&1; then
        DTACH_CMD="brew install dtach"
    elif command -v pacman >/dev/null 2>&1; then
        DTACH_CMD="sudo pacman -S --noconfirm dtach"
    elif command -v dnf >/dev/null 2>&1; then
        DTACH_CMD="sudo dnf install -y dtach"
    elif command -v apk >/dev/null 2>&1; then
        DTACH_CMD="sudo apk add dtach"
    fi

    if [[ -z "$DTACH_CMD" ]]; then
        echo "dtach is required but not installed."
        echo "Install it manually: https://github.com/cripty2001/dtach"
        exit 1
    fi

    echo "Installing dtach..."
    eval "$DTACH_CMD"
fi

# ─── Install grove ───────────────────────────────────────────────────────────

INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"

# Remove any existing file/symlink to avoid stale symlink issues
rm -f "$INSTALL_DIR/grove"
rm -f "$INSTALL_DIR/gr"

# If running from a local clone, symlink. Otherwise, download.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/grove" ]]; then
    ln -sf "$SCRIPT_DIR/grove" "$INSTALL_DIR/grove"
    ln -sf "$SCRIPT_DIR/grove" "$INSTALL_DIR/gr"
else
    curl -fsSL "https://raw.githubusercontent.com/dylangroos/grove/main/grove" \
        -o "$INSTALL_DIR/grove"
    chmod +x "$INSTALL_DIR/grove"
    ln -sf "$INSTALL_DIR/grove" "$INSTALL_DIR/gr"
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

# Shell completions
COMPLETION_LINE='eval "$(gr completions)"'
if ! grep -qF 'gr completions' "$PROFILE" 2>/dev/null; then
    echo "" >> "$PROFILE"
    echo "# grove shell completions" >> "$PROFILE"
    echo "$COMPLETION_LINE" >> "$PROFILE"
fi

echo "grove installed (grove + gr) — open a new terminal to start using it"
