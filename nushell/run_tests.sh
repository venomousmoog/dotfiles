#!/usr/bin/env bash
# Run nushell listing regression tests with the dotfiles config
DOTFILES="$(cd "$(dirname "$0")" && pwd)"
exec nu \
    --env-config "$DOTFILES/env.nu" \
    --config "$DOTFILES/config.nu" \
    "$DOTFILES/test_listing.nu"
