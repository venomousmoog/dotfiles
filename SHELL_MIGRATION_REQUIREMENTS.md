# Shell Migration Requirements

Distilled from analyzing the PowerShell profile (`powershell/profile.ps1`) and command history. These requirements are shell-agnostic -- they describe what we care about regardless of whether we go with nushell, elvish, or something else.

## Goal

Replace PowerShell with a cross-platform shell (Windows, Linux, macOS) that provides a consistent environment on all machines. The new shell config should feel as close to the current PowerShell experience as possible.

## Must-Have: File Listing

The current setup uses Terminal-Icons (Nerd Font glyphs + per-extension coloring) layered on top of PowerShell's native `Get-ChildItem`. The key properties we want to preserve:

**Display behavior:**
- Default view: compact/short (comparable to `Format-Wide -AutoSize` or a grid view)
- Long view via `-l` flag: table with permissions, date, size, name
- Hidden/dotfiles via `-a` flag
- Nerd Font icons prepended to file names, looked up by extension and well-known filename
- Colors per extension and well-known filename, matching `ddriver.theme.psd1` (~200 extension-to-color mappings)
- Directories grouped first

**Architecture preference:**
- Icons and colors should be a display/formatting layer, not baked into the data
- If the shell supports structured output (like nushell or elvish), piping `ls | sort-by size` should work on clean data with icons added only at display time
- This is how Terminal-Icons works in PowerShell (via `.format.ps1xml`)

**Source data files:**
- `powershell/Modules/Terminal-Icons/0.10.0/Data/iconThemes/devblackops.psd1` -- extension-to-icon mappings (Nerd Font glyph names)
- `powershell/ddriver.theme.psd1` -- extension-to-color mappings (hex colors)

## Must-Have: Prompt (oh-my-posh)

Keep using oh-my-posh. It supports PowerShell, bash, zsh, nushell, elvish, fish, and more. Config file: `powershell/ddriver.omp.json`. Reuse as-is.

oh-my-posh also handles:
- Git status in prompt
- Python virtualenv display (via `VIRTUAL_ENV_DISABLE_PROMPT=1`)

## Must-Have: Directory Jumping (zoxide / z)

The `z` command is heavily used (`z aria_ai`, `z paddle`, `z redirect`, etc.). Currently via `Import-Module z` in PowerShell. zoxide supports most shells natively.

## Must-Have: bat Aliases

- `cat` aliased to `bat`
- `less` aliased to `bat`
- `BAT_THEME=zenburn`
- `BAT_STYLE=grid,numbers`

## Must-Have: Dependency Check at Startup

Print a warning if any required tool is missing:
- `oh-my-posh`
- `bat`
- `zoxide`
- `eza` (optional, for grid view with icons)

Don't error out -- just warn and degrade gracefully.

## Must-Have: Cross-Platform PATH Setup

Platform-conditional PATH additions:
- All platforms: `$DOTFILES_PATH/Tools/<platform>`
- Linux: `/packages/adb/latest/`
- macOS: homebrew shellenv, `~/Library/Android/sdk/platform-tools/`
- Windows: debuggers, WinMerge, Android SDK, OneDrive tools

Platform detection must work reliably on all three OSes.

## Must-Have: Environment Variables

- `VIRTUAL_ENV_DISABLE_PROMPT = "1"`
- `BAT_THEME = "zenburn"`
- `BAT_STYLE = "grid,numbers"`
- `EDITOR = "code-fb --wait"`
- `USERNAME` set if missing (some platforms only set `USER`)

## Should-Have: tmux Integration

- `update-tmux-env` / `ue` command: sync `VSCODE_IPC_HOOK_CLI` and related env vars from `tmux show-environment`
- Update tmux window title on each prompt (using oh-my-posh with `tmux-title.omp.json`)
- **Guarded**: no-op when `$TMUX` is not set (i.e., on Windows or outside tmux)

## Should-Have: Python venv Activation

- `venv` command: walk up directory tree looking for `.venv/`, activate it
- Platform-aware: `.venv/Scripts/activate` on Windows, `.venv/bin/activate` on Unix
- Display the project name when activating

## Should-Have: Buck Build Helpers

Wrappers calling `python3 <dotfiles>/b/b.py <subcommand>`:
- `bb` (build), `br` (run), `bt` (test), `bq` (query), `bg` (targets), `bd` (debug)
- `b` (general), plus `*q` variants (bbq, brq, btq, bdq, bgq)
- `bmode` -- set/clear/query `BUCK_MODE` env var
- `udpb` -- update compilation database
- `tidy` -- run clang-tidy

Handle `python3` vs `python` differences on Windows.

## Should-Have: Reversed hg smartlog

- `sl` command: run `hg sl --color=always`, reverse the line order, swap `╯`↔`╮` and `╭`↔`╰` box-drawing characters

## Should-Have: Cross-Platform ln

- `ln` command with `-s` flag for symbolic links
- On Unix: delegate to system `ln`
- On Windows: use `cmd /c mklink` (with `/D` for directories, `/H` for hardlinks)
- If target is a directory, append the source filename

## Should-Have: grep --color

- Alias `grep` to `grep --color=auto`
- **Guarded**: only defined if `grep` binary exists (absent on vanilla Windows)

## Nice-to-Have: Completions

- docker, kubectl, podman completions (if the shell supports external completions)
- hg/mercurial completions
- The shell's native completion system should provide menu-style completion (like PSReadLine's `MenuComplete`)

## Dropped (Not Porting)

- `debug-coredump` -- never worked
- `sudo` (Windows RunAs) -- system `sudo` on Unix, not needed
- `windiff` / WinMerge alias -- Windows-specific
- `disk-usage.ps1` / `df` -- Windows-specific (uses Get-Volume); system `df` on Unix
- `pwto` (pastry pipe) -- low priority
- PSReadLine, PSBashCompletions, posh-git, posh-dotnet, posh-docker, posh-vs, PSfzf -- PowerShell-specific modules
- CommandNotFoundAction -- shell-specific
