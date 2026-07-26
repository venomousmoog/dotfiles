#!/usr/bin/env bash
set -euo pipefail

# Resolve dotfiles root (parent of the install/ directory this script lives in)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check for PowerShell
if ! command -v pwsh &>/dev/null; then
    echo "Error: PowerShell (pwsh) is not installed or not in PATH."
    echo ""
    echo "Install PowerShell:"
    echo "  Linux:  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
    echo "  macOS:  brew install --cask powershell"
    echo ""
    exit 1
fi

exec pwsh -NoProfile -File "$DOTFILES_ROOT/install/install.ps1" "$@"
