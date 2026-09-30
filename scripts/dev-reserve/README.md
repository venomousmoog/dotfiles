# DevReserve

A standalone native macOS menu-bar app for viewing active DevEnv reservations and reserving a selected OD for six days. It uses the local `dev` CLI directly and has no Agent Conductor dependency.

## Behavior

- Reads inventory with `dev -q list --with-reservable --json`.
- Shows active OD reservation countdowns and long-lived devservers.
- Searches enabled OD types returned by DevEnv, excluding types with known zero capacity.
- Reserves with a headless six-day `dev connect`: no shell, host setup, homedir upload, restore wait, or release prompt.
- Stores no Duo credentials. The app asks DevEnv to send a Duo push.
- Offers a Stop Waiting action and a 15-minute command deadline. Either outcome refreshes inventory because allocation may have completed before a later failure.
- Does not release, renew, or keep a lease alive. DevEnv owns the six-day lease after allocation, so quitting the app does not release it.

The effective reservation command is:

```bash
dev -q connect -t <type[:flavor]> --expiration 6 \
  --no-connect --no-connection-prompt --no-release-prompt \
  --skip-host-setup --skip-homedir --restore-state-in-background \
  --yubi push --entry-point dev_cli:dev_reserve_bar
```

The app adds `--hardware-option` and `--name` when selected.

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
