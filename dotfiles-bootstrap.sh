#!/usr/bin/env bash
# dotfiles-bootstrap.sh -- Wait for environment sync and ensure dotfiles repo is ready
#
# Source this from ~/.bashrc so that the environment is fully initialized
# before any dotfiles-dependent config (tmux, nushell, etc.) runs.
#
# NEW MACHINE SETUP: copy this file to ~/.config/dotfiles-bootstrap.sh
#   cp ~/src/dotfiles/dotfiles-bootstrap.sh ~/.config/dotfiles-bootstrap.sh
# This file must NOT be a symlink -- it must exist before dotfiles are cloned

DOTFILES_DIR="$HOME/src/dotfiles"

# Wait for dotsync2 to finish its initial pull. The dotfiles.target systemd
# unit activates once the pull completes, ensuring .tmux.conf, .bashrc, and
# other synced files are in place before we proceed.
if command -v systemctl &>/dev/null; then
    if ! systemctl --user is-active --quiet dotfiles.target 2>/dev/null; then
        printf "Waiting for dotfiles sync"
        _ds_elapsed=0
        while ! systemctl --user is-active --quiet dotfiles.target 2>/dev/null; do
            sleep 1
            _ds_elapsed=$((_ds_elapsed + 1))
            printf "."
            if [ $_ds_elapsed -ge 120 ]; then
                printf " timed out after 120s\n"
                break
            fi
        done
        if [ $_ds_elapsed -lt 120 ]; then
            printf " done (%ds)\n" "$_ds_elapsed"
        fi
        unset _ds_elapsed
    fi
fi

# Wait for Eden/feature initial sync (source code checkout)
if command -v feature &>/dev/null; then
    if ! feature status 2>/dev/null | grep -q "Initial sync: successful"; then
        printf "Waiting for feature sync"
        _fs_elapsed=0
        while ! feature status 2>/dev/null | grep -q "Initial sync: successful"; do
            sleep 5
            _fs_elapsed=$((_fs_elapsed + 5))
            printf "."
            if [ $_fs_elapsed -ge 300 ]; then
                printf " timed out after 300s\n"
                break
            fi
        done
        if [ $_fs_elapsed -lt 300 ]; then
            printf " done (%ds)\n" "$_fs_elapsed"
        fi
        unset _fs_elapsed
    fi
fi

# Clone dotfiles repo if missing
if [ ! -d "$DOTFILES_DIR" ]; then
    mkdir -p "$HOME/src"
    echo "Cloning dotfiles repository..."
    _git_proxy=$(fwdproxy-config git 2>/dev/null)
    git $_git_proxy clone --recurse-submodules https://github.com/venomousmoog/dotfiles "$DOTFILES_DIR"
    unset _git_proxy
elif [ -f "$DOTFILES_DIR/.gitmodules" ]; then
    _git_proxy=$(fwdproxy-config git 2>/dev/null)
    (cd "$DOTFILES_DIR" && git $_git_proxy submodule update --init --recursive 2>/dev/null)
    unset _git_proxy
fi

# Ensure OS-specific gitconfig is linked
if [ ! -e "$HOME/.gitconfig.os" ] && [ -f "$DOTFILES_DIR/git/gitconfig.linux.meta" ]; then
    ln -s "$DOTFILES_DIR/git/gitconfig.linux.meta" "$HOME/.gitconfig.os"
fi

# On an OnDemand host (<id>.od.fbinfra.net), seed each enlistment root's
# .vscode/markdown-styles.css so the docs/ stylesheet renders previews
# regardless of which checkout the editor is opened against.
case "$(hostname -f 2>/dev/null || hostname)" in
    *.od.fbinfra.net)
        _md_src="$DOTFILES_DIR/docs/markdown-styles.css"
        if [ -f "$_md_src" ]; then
            for _root in \
                /data/sandcastle/boxes/fbsource \
                /data/sandcastle/boxes/configerator \
                /data/sandcastle/boxes/www \
                "$HOME/fbsource" \
                "$HOME/configerator" \
                "$HOME/www"
            do
                if [ -d "$_root" ]; then
                    mkdir -p "$_root/.vscode"
                    cp "$_md_src" "$_root/.vscode/markdown-styles.css"
                fi
            done
            unset _root
        fi
        unset _md_src
        ;;
esac
