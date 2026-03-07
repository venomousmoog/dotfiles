# Tmux Dotfiles Migration — Session State

## Completed (via file tools)

- Created `~/src/dotfiles/dotfiles-bootstrap.sh` (canonical shared bootstrap script)
- Copied to `~/.config/dotfiles-bootstrap.sh` (local copy)
- Moved all files from `~/.tmux/` to `~/src/dotfiles/tmux/`:
  - `update_theme.sh`, `update_theme_v2.sh`
  - `claude_sessions.py`, `claude_sessions_v2.py`
  - `default-status-format-0.txt`
  - `plugin/` directory (hooks, .claude-plugin, commands)
- Created `~/src/dotfiles/tmux/tmux.conf` (real config, `update_theme.sh` path updated)
- Created `~/src/dotfiles/tmux/tmux.conf.stub` (canonical copy of bootstrap stub)
- Replaced `~/.tmux.conf` with thin bootstrap stub that sources from dotfiles
- Updated `update_theme.sh`: `~/.tmux/claude_sessions.py` → `~/src/dotfiles/tmux/claude_sessions.py`
- Updated `update_theme_v2.sh`: `~/.tmux/claude_sessions_v2.py` → `~/src/dotfiles/tmux/claude_sessions_v2.py`
- Updated `update_theme_v2.sh` comments to reflect new paths
- Updated all 6 hook paths in `~/.claude/settings.json`: `~/.tmux/plugin/hooks/` → `~/src/dotfiles/tmux/plugin/hooks/`
- Updated `~/.config/nushell/env.nu` to use shared bootstrap
- Updated `~/src/dotfiles/nushell/env.nu` (canonical copy) to use shared bootstrap

## Remaining manual steps (shell was broken — CWD landed in deleted directory)

Run these in a terminal:

```bash
# 1. Clean up leftover __pycache__
rm -rf ~/.tmux/__pycache__

# 2. Add tmux-minimal-theme as a git submodule
cd ~/src/dotfiles
git submodule add https://github.com/binoymanoj/tmux-minimal-theme.git tmux/plugins/tmux-minimal-theme

# 3. Create the ~/.tmux/plugins symlink
mkdir -p ~/.tmux
ln -s ~/src/dotfiles/tmux/plugins ~/.tmux/plugins
```

## Verification (run after manual steps)

```bash
# Submodule registered
git -C ~/src/dotfiles submodule status

# Symlink resolves
ls -la ~/.tmux/plugins
ls ~/.tmux/plugins/tmux-minimal-theme/minimal.tmux

# Reload tmux config (confirm no errors, status bar renders)
tmux source-file ~/.tmux.conf

# Git status — all new files tracked, submodule registered
git -C ~/src/dotfiles status

# Start a new Claude Code session — confirm statusline hooks fire
# Open a new nushell session — confirm env.nu works with shared bootstrap
```

## File inventory in ~/src/dotfiles/tmux/

```
tmux/
├── tmux.conf                          # Real config (sourced by stub)
├── tmux.conf.stub                     # Canonical copy of ~/.tmux.conf bootstrap stub
├── update_theme.sh                    # Theme setup (path updated)
├── update_theme_v2.sh                 # Tunnel-aware theme (path updated)
├── claude_sessions.py                 # Status bar session manager
├── claude_sessions_v2.py              # Tunnel-aware session manager
├── default-status-format-0.txt        # Default status format
├── plugins/
│   └── tmux-minimal-theme/            # Git submodule (pending add)
└── plugin/
    ├── .claude-plugin/plugin.json     # Claude Code plugin manifest
    ├── commands/setup.md              # Plugin setup command
    └── hooks/
        ├── _lib.sh                    # Shared hook library
        ├── notification.sh
        ├── pre-tool-use.sh
        ├── session-end.sh
        ├── session-start.sh
        ├── stop.sh
        └── user-prompt-submit.sh
```
