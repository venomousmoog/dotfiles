---
description: Configure tmux to show Claude agent status bar
---

# Setup tmux Statusline

Help the user configure their tmux to show Claude agent indicators.

**IMPORTANT**: Even if the user already has a working configuration, you MUST still:
1. Verify it's working correctly
2. Offer icon customization (Step 6)
3. Provide the icon legend
Do NOT skip steps just because the setup appears complete.

---

## Step 0: Check Prerequisites

Before modifying any configuration, verify these requirements are met:

```bash
# Check Python version (needs 3.9+)
python3 --version

# Check jq is installed (required for hook scripts)
which jq

# Check tmux version (needs 2.9+ for multiple status lines)
tmux -V
```

If any are missing or outdated, help the user install them:

```bash
# Install jq if missing:
# Ubuntu/Debian: sudo apt-get install jq
# macOS: brew install jq
# Fedora: sudo dnf install jq

# Install/upgrade Python if needed:
# Ubuntu/Debian: sudo apt-get install python3
# macOS: brew install python@3.11
```

---

## Step 1: Determine Plugin Path

Find where `constellation.py` is installed:

```bash
# Check production path (from /plugin install)
if [ -f ~/.local/share/claude/plugins/tmux-statusline/bin/constellation.py ]; then
    echo "Found: production install"
    echo "Path: ~/.local/share/claude/plugins/tmux-statusline/bin/constellation.py"
# Check dev path (from --dev install)
elif [ -f ~/.claude-templates-dev/components/plugins/tmux-statusline/bin/constellation.py ]; then
    echo "Found: dev install"
    echo "Path: ~/.claude-templates-dev/components/plugins/tmux-statusline/bin/constellation.py"
else
    echo "ERROR: Plugin not installed. Run: /plugin install tmux-statusline@claude-templates"
fi
```

Use whichever path exists. If neither exists, the plugin is not installed - ask the user to run `/plugin install tmux-statusline@claude-templates` first.

**IMPORTANT:** Use the correct path in all configuration examples below. Replace `/path/to/constellation.py` with the actual path found above.

---

## Step 1b: Comprehensive Configuration Check

Let the user know you are looking for existing configurations of the tmux-statusline plugin...

Search ALL common locations for existing configuration:

```bash
# Search for constellation.py references everywhere
echo "=== Searching for existing constellation.py configuration ==="
grep -r "constellation.py" \
    ~/.tmux.conf \
    ~/.config/tmux-powerline/ \
    ~/.tmux/ \
    2>/dev/null | grep -v ".bak"

# Search for @claude window option usage
echo ""
echo "=== Searching for @claude window option usage ==="
grep -r "@claude" \
    ~/.tmux.conf \
    ~/.config/tmux-powerline/ \
    2>/dev/null | grep -v ".bak"

# Check for custom powerline segment
if [ -f ~/.config/tmux-powerline/segments/claude_status.sh ]; then
    echo ""
    echo "=== Found existing claude_status.sh segment ==="
    cat ~/.config/tmux-powerline/segments/claude_status.sh
fi

# Test if @claude is currently being set
echo ""
echo "=== Current @claude value (if tmux running) ==="
tmux show-window-option -v @claude 2>/dev/null || echo "(not set or tmux not running)"

# Detect tmux-powerline installation
if [ -d ~/.config/tmux-powerline ]; then
    echo ""
    echo "=== tmux-powerline detected ==="
    echo "Segments directory:"
    ls ~/.config/tmux-powerline/segments/ 2>/dev/null || echo "(no custom segments)"
    echo ""
    echo "Checking themes for @claude:"
    grep -l "@claude" ~/.config/tmux-powerline/themes/*.sh 2>/dev/null || echo "(not found in themes)"
fi
```

**If existing configuration is found:** Verify it's working before making changes. The user may already have a complete setup. Ask them if the icons are appearing correctly before proceeding with modifications.

---
### ⛔ STOP — Wait for User Response (if existing config found)
<!-- DO NOT display this STOP gate to the user - it is an internal instruction -->

If the above checks found existing constellation.py or @claude configuration, DO NOT proceed until the user confirms:
1. "Yes, icons are working" → Skip to Step 6 (icon customization)
2. "No, icons aren't showing" → Continue with setup/troubleshooting
3. "I want to reconfigure" → Continue with Step 2

**You MUST wait for the user to reply before continuing.**

---

## Step 2: Choose Display Mode

There are two display modes. Ask the user which they prefer:

### Mode 1: Constellation Bar (Recommended for most users)
- Adds a dedicated status line showing all agents
- Display: `[1:🟢] [2:🟡 3m] [3:⚪]`
- Easiest to configure, works with any tmux setup
- Uses `status 2` for a second status line

### Mode 2: Per-Tab Indicators
- Integrates icons directly into window/tab names
- Display: `1:bash 🟢 | 2:claude 🟡 | 3:vim`
- No extra status line needed - saves vertical space
- Requires modifying window-status-format
- Best for users with powerline/tmux-powerline who want inline indicators

---
### ⛔ STOP — Wait for User Response
<!-- DO NOT display this STOP gate to the user - it is an internal instruction -->

DO NOT proceed until the user has chosen a display mode.

Valid user responses include:
- "1" / "Mode 1" / "Constellation Bar"
- "2" / "Mode 2" / "Per-Tab"
- A clear preference statement

**You MUST wait for the user to reply before continuing.**

---

## Step 3: Backup and Inspect Configuration

Before modifying any user config files, ALWAYS:

### 3a. Create Timestamped Backups

```bash
# Backup tmux.conf before editing
cp ~/.tmux.conf ~/.tmux.conf.bak.$(date +%Y%m%d%H%M%S)

# For Mode 2 with powerline, also backup (replace THEME with actual theme name, e.g., default):
cp ~/.config/tmux-powerline/themes/THEME.sh ~/.config/tmux-powerline/themes/THEME.sh.bak.$(date +%Y%m%d%H%M%S)
cp ~/.config/tmux-powerline/config.sh ~/.config/tmux-powerline/config.sh.bak.$(date +%Y%m%d%H%M%S)
```

### 3b. Check for Existing Configuration

**Avoid duplicates:** Check if constellation is already configured:

```bash
# Check for existing constellation configuration
if grep -q "constellation.py" ~/.tmux.conf 2>/dev/null; then
    echo "WARNING: constellation.py already configured at:"
    grep -n "constellation.py" ~/.tmux.conf
    echo "Remove these lines before proceeding, or update them in place."
fi

if grep -q "status 2" ~/.tmux.conf 2>/dev/null; then
    echo "NOTE: 'status 2' already set - you may not need to add it again"
fi
```

If constellation is already configured, either:
1. Remove the existing lines before adding new ones, or
2. Update the existing configuration in place

### 3c. Inspect Current Setup

```bash
# Read their tmux config
cat ~/.tmux.conf

# Check current status settings (if tmux is running)
tmux show-options -g | grep -E "^status"
```

---

## Mode 1: Constellation Bar Setup

### Step 1: Add Configuration

**Placement is critical:** Add these lines AFTER all other plugin initializations:
- After TPM: `run '~/.tmux/plugins/tpm/tpm'`
- After powerline-status: `run-shell "powerline-daemon ..."`
- After tmux-powerline: Any lines that source powerline.sh
- As the absolute last lines in the file

**For users with customized status bar (MOST USERS):**

Add the Constellation Bar as an ADDITIONAL line at the VERY END of `~/.tmux.conf`:

```bash
# Claude Code agent Constellation Bar
# ADD this at the VERY END of tmux.conf (after TPM, powerline, etc.)
set -g status 2
set -g status-format[1] '#(python3 /path/to/constellation.py)'
set -g status-interval 2  # Refresh every 2 seconds for responsive updates
```

**For users with minimal/default tmux config:**

```bash
# Claude Code agent Constellation Bar
set -g status 2
set -g status-format[1] '#(python3 /path/to/constellation.py)'
set -g status-format[0] '#[align=left]#{W:#I:#W }#[align=right]%H:%M'
set -g status-interval 2
```

### Step 2: Test and Reload

```bash
# Test without permanent changes (use actual path from Step 1):
tmux set -g status 2
tmux set -g status-format[1] '#(python3 /path/to/constellation.py)'
tmux set -g status-interval 2

# After editing tmux.conf, reload:
tmux source ~/.tmux.conf
```

### Step 3: Verify Installation

1. Test the script runs without errors:
```bash
python3 /path/to/constellation.py
# Should output nothing (no agents running yet) or show current agents
# Example output when agents are running: [1:🟢] [2:⚪]
```

2. Start a new Claude session in tmux and verify the indicator appears:
   - White (⚪) = Session started, waiting for input
   - Green (🟢) = Agent is working after you submit a prompt

If the Constellation Bar doesn't appear, check the Troubleshooting section.

---

## Mode 2: Per-Tab Indicators Setup

This mode requires two parts:
1. A trigger that runs constellation.py to set window options
2. Adding `#{@claude}` to your window-status-format

**Note:** If using per-tab mode, do NOT set `status 2` - you don't need an extra line.

### Step 1: Add the Trigger

**Placement:** Add these lines AFTER all other plugin initializations, at the very end of `~/.tmux.conf`:

```bash
# Claude Code per-tab indicators - trigger to update @claude window options
# This outputs nothing; it just sets the @claude option on each window
# Use --space-before and/or --space-after to add spacing around icons
set -ga status-right '#(python3 /path/to/constellation.py --per-tab --space-before)'
set -g status-interval 2  # Refresh every 2 seconds
```

**Spacing options:**
- `--space-before`: Adds space before icon (e.g., ` 🟢`)
- `--space-after`: Adds space after icon (e.g., `🟢 `)
- Both flags: ` 🟢 ` (space on both sides)
- Windows without agents get empty string (no extra spaces)

### Step 2: Add #{@claude} to Window Format

**For tmux-powerline users (erikw/tmux-powerline):**

Edit `~/.config/tmux-powerline/config.sh` and add/modify:

```bash
# Icon BEFORE window name (use with --space-after):
TMUX_POWERLINE_WINDOW_STATUS_FORMAT=(
    "#[$(format regular)]"
    "  #I#{?window_flags,#F, } "
    "$TMUX_POWERLINE_SEPARATOR_RIGHT_THIN"
    "#{@claude}#W "
)

# Or icon AFTER window name (use with --space-before):
TMUX_POWERLINE_WINDOW_STATUS_FORMAT=(
    "#[$(format regular)]"
    "  #I#{?window_flags,#F, } "
    "$TMUX_POWERLINE_SEPARATOR_RIGHT_THIN"
    " #W#{@claude}"
)
```

**Note:** Remove static spaces around `#{@claude}` and use the spacing flags instead. This ensures no extra spaces appear when there's no agent.

**For standard tmux (no powerline):**

Add to `~/.tmux.conf`:

```bash
# Add Claude indicator to window tabs
set -g window-status-format '#I:#W#{@claude}'
set -g window-status-current-format '#I:#W#{@claude}'
```

**For users who want to override powerline in tmux.conf:**

Add at the VERY END of `~/.tmux.conf` (after TPM initialization):

```bash
# Override powerline window format to include Claude indicator
set -g window-status-format "#(/path/to/powerline.sh window-format)#{@claude}"
set -g window-status-current-format "#(/path/to/powerline.sh window-current-format)#{@claude}"
```

### Step 3: Test and Reload

```bash
# Reload tmux config
tmux source ~/.tmux.conf

# Verify @claude is being set (should show icon like " 🟢" or empty string)
tmux show-window-option @claude
# Example output: @claude  🟢
```

### Step 4: Verify Installation

1. Test the script runs without errors:
```bash
python3 /path/to/constellation.py --per-tab
# Should output nothing (sets @claude options silently)
```

2. Start a new Claude session in tmux and verify the indicator appears in the tab:
   - White (⚪) = Session started, waiting for input
   - Green (🟢) = Agent is working after you submit a prompt
   - No icon = Window has no Claude agent

If icons don't appear, check the Troubleshooting section.

---

## Step 6: Offer Icon Customization (REQUIRED to ask)

After verifying the setup works, ALWAYS ask the user about icon customization:

"Your current icons are:
- 🟢 Working (thinking/executing)
- 🟡 Waiting (needs your attention)
- ⚪ Acknowledged (you've seen it)

Would you like to customize any of these? Common options:
1. Change 🟡 to ⚠️ (more attention-grabbing)
2. Change ⚪ to 🔵 (better visibility on light backgrounds)
3. Use minimal ASCII: ● ○ ·
4. Use the defaults [show what they are]
5. Keep current setup [if they already have icons configured, show what they have]

---
### ⛔ STOP — Wait for User Response
<!-- DO NOT display this STOP gate to the user - it is an internal instruction -->

DO NOT proceed to the Final Checklist until the user has responded to the icon customization question.

Valid user responses include:
- A number selecting an option (e.g., "1", "2", "3")
- "keep current" / "no changes" / "keep"
- A custom icon request (e.g., "change ⚪ to 🔵")
- "skip" / "none" / "default"

**You MUST wait for the user to reply before continuing.**

---

**To customize, add icon flags to the constellation.py command:**

```bash
# Example: Change acknowledged icon to blue (for light status bars)
python3 /path/to/constellation.py --acknowledged-icon "🔵"

# Example: Change all icons
python3 /path/to/constellation.py --working-icon "🟢" --waiting-icon "🟡" --acknowledged-icon "🔵"

# Example: Minimal ASCII icons
python3 /path/to/constellation.py --working-icon "●" --waiting-icon "○" --acknowledged-icon "·"
```

**Available icon flags:**
- `--working-icon "X"` - Icon for working/thinking state (default: 🟢)
- `--waiting-icon "X"` - Icon for waiting/attention state (default: 🟡)
- `--acknowledged-icon "X"` - Icon for acknowledged/dismissed state (default: ⚪)

**Note:** Users should test that their terminal renders the chosen icons correctly. The icons are just strings, so any text/emoji/symbol that their terminal supports will work.

---

## Icon Legend

- 🟢 Working (thinking/executing)
- 🟡 Waiting + unacknowledged (demands attention) + duration
- ⚪ Waiting + acknowledged (user has seen it)

Windows without agents show nothing (empty string) to save horizontal space.

## Troubleshooting

### Constellation Bar not appearing

1. Verify plugin is installed: `/plugin list`
2. Test the script directly: `python3 /path/to/constellation.py`
3. Check tmux sees 2 status lines: `tmux show-option -g status`
4. Ensure settings are at the VERY END of tmux.conf (after TPM, powerline, etc.)

### Per-tab indicators not appearing

1. Test the script: `python3 /path/to/constellation.py --per-tab`
2. Check @claude is set: `tmux show-window-option @claude`
3. Verify `#{@claude}` is in your window-status-format
4. Check status-interval is reasonable (2 seconds recommended)

### Existing status bar is broken

1. Constellation Bar should be on status-format[1], not [0]
2. Check that settings are at the VERY END of tmux.conf
3. Remove the Constellation Bar settings to revert

### Reverting Changes

If something went wrong, restore from backup:

```bash
# Find your backups
ls ~/.tmux.conf.bak.*

# Restore the most recent backup (replace YYYYMMDDHHMMSS with actual timestamp)
cp ~/.tmux.conf.bak.YYYYMMDDHHMMSS ~/.tmux.conf

# Reload tmux
tmux source ~/.tmux.conf
```

For powerline config backups:
```bash
ls ~/.config/tmux-powerline/*.bak.*
cp ~/.config/tmux-powerline/config.sh.bak.YYYYMMDDHHMMSS ~/.config/tmux-powerline/config.sh
```

---

## Step 7: Shell Integration (Optional)

After the tmux statusline is configured, offer to add a shell wrapper that automatically opens Claude in a new tmux session. This ensures users always get the benefits of the statusline indicators.

**Ask the user:**

"Would you like to add a shell wrapper so that running `claude` automatically opens in a new tmux session?

Benefits:
- Running `claude` outside tmux will automatically create a new tmux session
- You'll always see the constellation status indicators
- If already in tmux, `claude` runs normally (no nested sessions)

Options:
1. Yes, add the shell wrapper to ~/.bashrc
2. Yes, add the shell wrapper to ~/.zshrc
3. No, skip this step"

---
### ⛔ STOP — Wait for User Response
<!-- DO NOT display this STOP gate to the user - it is an internal instruction -->

DO NOT proceed until the user has responded to the shell integration question.

**You MUST wait for the user to reply before continuing.**

---

### If user wants shell integration:

**Step 7a: Backup shell config**

```bash
# For bash users:
cp ~/.bashrc ~/.bashrc.bak.$(date +%Y%m%d%H%M%S)

# For zsh users:
cp ~/.zshrc ~/.zshrc.bak.$(date +%Y%m%d%H%M%S)
```

**Step 7b: Check if wrapper already exists**

```bash
# Check for existing claude function
grep -n "^claude()" ~/.bashrc ~/.zshrc 2>/dev/null
```

If found, inform the user and skip adding (or offer to update the existing function).

**Step 7c: Add the shell wrapper function**

Add the following to the user's shell config file (`~/.bashrc` or `~/.zshrc`):

```bash
# Claude Code tmux wrapper - automatically opens Claude in a new tmux session
# Added by tmux-statusline plugin setup
claude() {
  if [ -z "$TMUX" ]; then
    # Not in tmux - create a new session with Claude
    session="claude-$(date +%s)"
    tmux new-session -s "$session" "claude $*"
  else
    # Already in tmux - run Claude directly
    command claude "$@"
  fi
}
```

**Step 7d: Apply the changes**

```bash
# For bash users:
source ~/.bashrc

# For zsh users:
source ~/.zshrc
```

**Step 7e: Verify the wrapper works**

```bash
# Check the function is defined
type claude

# Test it (should show function definition including tmux logic)
```

**Explanation of the wrapper:**
- `[ -z "$TMUX" ]` - Checks if we're already inside a tmux session
- If NOT in tmux: Creates a new tmux session with a unique name (`claude-<timestamp>`) and runs Claude inside it
- If IN tmux: Runs the actual `claude` binary directly using `command claude` to avoid recursion
- `$*` vs `$@`: Uses `$*` in the tmux command for proper argument passing to the nested shell

---

## Final Checklist (ALWAYS complete before finishing)

Before concluding the setup, verify you have:

- [ ] Confirmed prerequisites are met (Python 3.9+, jq, tmux 2.9+)
- [ ] Found or installed constellation.py
- [ ] Either set up new configuration OR verified existing configuration works
- [ ] Asked user about icon customization (even if they decline)
- [ ] Provided the icon legend
- [ ] Tested that icons appear correctly in tmux
- [ ] Offered shell integration option (even if they decline)

Only after completing this checklist should you consider the setup complete.
