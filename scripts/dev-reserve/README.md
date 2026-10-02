# DevReserve

A standalone native macOS menu-bar app for viewing and releasing active DevEnv reservations and reserving a selected OD for 1, 2, 3, or 6 days. It uses the local `dev` CLI directly and has no Agent Conductor dependency.

## Behavior

- Reads inventory with `dev -q list --with-reservable --json`.
- Uses a taller 500 × 760 popover, native macOS translucent materials, and compact section labels; the host list intentionally has no redundant top-level heading.
- Shows active OD reservation countdowns, inactive short-term Devserver V2 leases, and long-lived devservers in separate sections.
- Refreshes the 500 most recent Agentcloud sessions every five minutes through `agentcloudctl fleet --sort recent --limit 500` and resolves node aliases and lease claims through `agentcloudctl node list`.
- Shows every working Agentcloud session directly beneath its host in the main Reservations view. Non-working sessions stay compact behind an expandable `N attached` row; lease holders, canonical TTL/UTC expiry, and session links remain inline with the host.
- Copies a hostname when its displayed host name is clicked; there is no separate copy button.
- Opens the selected terminal when the icon beside a host is clicked. The persisted footer picker supports iTerm (default, new tab) and Apple's Terminal (new window), then runs `ssh <hostname>`. iTerm launch waits for the new shell session to become ready before sending the command; first use may ask for macOS Automation permission.
- Searches enabled OD types returned by DevEnv, excluding types with known zero capacity.
- Persists starred OD types locally and sorts favorites to the top of the searchable list.
- Reserves for a selected 1-, 2-, 3-, or 6-day duration, defaulting to six days, with a headless `dev connect`: no shell, host setup, homedir upload, restore wait, or release prompt.
- Releases an active OD only after an explicit destructive confirmation, using its validated hostname to avoid an interactive prompt.
- Stores no Duo credentials. The app asks DevEnv to send a Duo push.
- Keeps reservation work running when the menu-bar popover closes and sends a macOS banner for success or failure. Notification permission is requested on the first reservation attempt; the result also remains visible in the app.
- Shows a close button on operation, refresh, Agentcloud, and login-item error banners so acknowledged errors can be cleared; a later failure can surface again.
- Offers a Stop Waiting action and a 15-minute reservation deadline. Releases have a two-minute deadline. Either outcome refreshes inventory because the server-side operation may have completed before a later local failure.
- Does not renew or keep a lease alive. DevEnv owns the lease after allocation, so quitting the app does not release it. Release occurs only after the user confirms the trash action for a specific active OD.

The effective reservation command is:

```bash
dev -q connect -t <type[:flavor]> --expiration <1|2|3|6> \
  --no-connect --no-connection-prompt --no-release-prompt \
  --skip-host-setup --skip-homedir --restore-state-in-background \
  --yubi push --entry-point dev_cli:dev_reserve_bar
```

The app adds `--hardware-option` and `--name` when selected. An explicitly confirmed release uses:

```bash
dev -q release --hostname <hostname>
```

## Build and test

```bash
scripts/dev-reserve/test.sh
scripts/dev-reserve/build-app.sh
```

The test script formats/lints Swift, validates the shell/plist files, runs framework-free unit assertions, and parses the live read-only DevEnv inventory. The framework-free runner is intentional because this machine's Apple Command Line Tools image does not ship working XCTest or Swift Testing macro plugins.

The build script creates an ad-hoc-signed app at `dist/DevReserve.app`.

## Install at login

```bash
scripts/dev-reserve/install.sh
```

This installs the app to `~/Applications/DevReserve.app`, launches it, and lets the app register itself with macOS's supported `SMAppService` login-item API. If macOS requires approval, the popover links the required System Settings location in its status text.

Preview installation without changing `~/Applications`:

```bash
scripts/dev-reserve/install.sh --dry-run
```

To remove the app and unregister its login item:

```bash
scripts/dev-reserve/uninstall.sh
```

## Requirements

- macOS 14 or newer
- Swift 6 command-line tools
- The Meta `dev` CLI at `/usr/local/bin/dev`, `/opt/homebrew/bin/dev`, or on `PATH`
- The Meta `agentcloudctl` CLI at `/usr/local/bin/agentcloudctl`, `/opt/homebrew/bin/agentcloudctl`, or on `PATH` for session-usage hover details
- iTerm2 is optional; Apple's built-in Terminal is also supported by the per-host terminal button
