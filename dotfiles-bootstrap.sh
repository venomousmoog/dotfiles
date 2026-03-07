#!/usr/bin/env bash
# dotfiles-bootstrap.sh -- Ensure dotfiles repo is cloned and submodules initialized
#
# NEW MACHINE SETUP: copy this file to ~/.config/dotfiles-bootstrap.sh
#   cp ~/src/dotfiles/dotfiles-bootstrap.sh ~/.config/dotfiles-bootstrap.sh
# This file must NOT be a symlink -- it must exist before dotfiles are cloned

DOTFILES_DIR="$HOME/src/dotfiles"

if [ ! -d "$DOTFILES_DIR" ]; then
    mkdir -p "$HOME/src"
    echo "Cloning dotfiles repository..."
    git clone --recurse-submodules https://github.com/venomousmoog/dotfiles "$DOTFILES_DIR"
fi

# Init submodules if any are missing (handles repos cloned without --recurse-submodules)
if [ -f "$DOTFILES_DIR/.gitmodules" ]; then
    cd "$DOTFILES_DIR"
    git submodule update --init --recursive 2>/dev/null
fi
