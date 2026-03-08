#!/usr/bin/env bash
set -euo pipefail

# Resolve dotfiles root (parent of the install/ directory this script lives in)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check for nushell
if ! command -v nu &>/dev/null; then
    echo "Error: nushell (nu) is not installed or not in PATH."
    echo ""
    echo "Install nushell:"
    echo "  Linux:  cargo install nu  OR  https://www.nushell.sh/book/installation.html"
    echo "  macOS:  brew install nushell"
    echo ""
    exit 1
fi

exec nu "$DOTFILES_ROOT/install/install.nu" "$@"
