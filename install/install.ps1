#!/usr/bin/env pwsh

# Cross-platform dotfiles installer (PowerShell).
#
# PowerShell runs on Linux, macOS, and Windows, so a single .ps1 covers every
# platform. It symlinks (or copies) each configured file into place. Run with:
#
#   pwsh install/install.ps1            # apply
#   pwsh install/install.ps1 -DryRun    # show what would happen, change nothing

[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$dotfilesRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$platform =
    if     ($IsWindows) { 'windows' }
    elseif ($IsMacOS)   { 'macos' }
    elseif ($IsLinux)   { 'linux' }
    else { throw "Unsupported platform" }

# On Meta hosts, prefer a "<source>.meta" variant of a source file when present.
$hostName = try { hostname } catch { $env:HOSTNAME }
$isMeta = [bool]($hostName -match 'facebook')

Write-Host "Platform: $platform$(if ($isMeta) { ' (meta)' })"
if ($DryRun) { Write-Host '[DRY RUN] No changes will be made.' }
Write-Host ''

# Link table. Each entry:
#   source : repo-relative path; "{platform}" is substituted with the platform.
#   method : 'symlink' or 'copy'.
#   target : a single path (all platforms) OR a hashtable of per-platform paths.
#            An entry with no target for the current platform is skipped.
# "~" in a target expands to the home directory.
$links = @(
    # --- git ---
    # ~/.gitconfig is a real file (copied stub), NOT a symlink into the repo, so
    # that `git config --global ...` writes (e.g. the Meta agent launcher's x509
    # cert setup) land locally instead of dirtying the tracked git/gitconfig.
    # The stub just `[include]`s git/gitconfig, which itself includes .gitconfig.os.
    @{ source = 'git/gitconfig.local.stub'; method = 'copy';    target = '~/.gitconfig' }
    @{ source = 'git/gitconfig.{platform}'; method = 'symlink'; target = '~/.gitconfig.os' }

    # --- tmux ---
    @{ source = 'tmux/tmux.conf.stub'; method = 'copy'; target = @{ linux = '~/.tmux.conf'; macos = '~/.tmux.conf' } }

    # --- powershell ---
    @{ source = 'powershell/profile.ps1.stub'; method = 'copy'; target = @{
        linux   = '~/.config/powershell/Microsoft.PowerShell_profile.ps1'
        macos   = '~/.config/powershell/Microsoft.PowerShell_profile.ps1'
        windows = '~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
    } }

    # --- markdown styles (single source of truth in docs/) ---
    @{ source = 'docs/markdown-styles.css'; method = 'symlink'; target = '~/markdown-styles.css' }
    @{ source = 'docs/markdown-styles.css'; method = 'symlink'; target = '~/.vscode/markdown-styles.css' }

    # --- windows terminal ---
    @{ source = 'terminal/settings.json'; method = 'symlink'; target = @{ windows = '~/AppData/Local/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json' } }

    # --- vscode / vsc-meta settings (disabled: the editor rewrites settings.json,
    #     so it isn't symlinked. Uncomment a line to opt back in on that OS.) ---
    # @{ source = 'vscode/settings.json';  method = 'symlink'; target = @{ windows = '~/AppData/Roaming/Code - Insiders/User/settings.json'; macos = '~/Library/Application Support/Code - Insiders/User/settings.json' } }
    # @{ source = 'vsc-meta/settings.json'; method = 'symlink'; target = @{ windows = '~/AppData/Roaming/VS Code @ FB - Dev/User/settings.json'; macos = '~/Library/Application Support/VS Code @ FB - Dev/User/settings.json' } }

    # --- kanata (Caps = tap Esc / hold Command layer; mirrors the Corne firmware) ---
    # Self-contained per-OS config; symlinked to the kanata config dir as kanata.kbd.
    @{ source = 'kanata/kanata.macos.kbd'; method = 'symlink'; target = @{ macos = '~/.config/kanata/kanata.kbd' } }
    @{ source = 'kanata/kanata.ctrl.kbd';  method = 'symlink'; target = @{ linux = '~/.config/kanata/kanata.kbd'; windows = '~/AppData/Roaming/kanata/kanata.kbd' } }

    # --- vscode keybindings (macOS: selection-aware cmd+c in integrated terminal) ---
    @{ source = 'vscode/keybindings.json';  method = 'symlink'; target = @{ macos = '~/Library/Application Support/Code - Insiders/User/keybindings.json' } }
    @{ source = 'vsc-meta/keybindings.json'; method = 'symlink'; target = @{ macos = '~/Library/Application Support/VS Code @ FB - Dev/User/keybindings.json' } }
)

function Expand-HomePath([string]$p) {
    if ($p -like '~*') { return (Join-Path $HOME $p.Substring(1).TrimStart('/', '\')) }
    return $p
}

$created = 0; $updated = 0; $skipped = 0; $backedUp = 0

foreach ($entry in $links) {
    # Resolve the target for this platform.
    $targetRaw = if ($entry.target -is [hashtable]) {
        if ($entry.target.ContainsKey($platform)) { $entry.target[$platform] } else { $null }
    } else {
        $entry.target
    }
    if ($null -eq $targetRaw) { continue }

    # Resolve the source: substitute {platform}, then prefer a .meta variant on Meta hosts.
    $sourceResolved = $entry.source -replace '\{platform\}', $platform
    $sourcePath = Join-Path $dotfilesRoot $sourceResolved
    if ($isMeta) {
        $metaPath = "$sourcePath.meta"
        if (Test-Path -LiteralPath $metaPath) { $sourcePath = $metaPath }
    }

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-Host "  [skip] source not found: $sourcePath" -ForegroundColor Yellow
        $skipped++
        continue
    }
    $sourceFull = (Resolve-Path -LiteralPath $sourcePath).Path

    $targetPath = Expand-HomePath $targetRaw
    $targetDir  = Split-Path -Parent $targetPath
    $bakPath    = "$targetPath.bak"

    $exists = Test-Path -LiteralPath $targetPath

    if ($entry.method -eq 'symlink') {
        # Already the correct symlink?
        $isCorrect = $false
        if ($exists) {
            $item = Get-Item -LiteralPath $targetPath -Force
            if ($item.LinkType -eq 'SymbolicLink') {
                $current = $item.Target
                if ($current -is [array]) { $current = $current[0] }
                $isCorrect = ($current -eq $sourceFull) -or ($current -eq $sourcePath)
            }
        }

        if ($isCorrect) {
            Write-Host "  [skip] $targetPath -> $sourceFull (already correct)"
            $skipped++
        } elseif ($DryRun) {
            if ($exists) {
                Write-Host "  [backup] $targetPath -> $bakPath"
                Write-Host "  [symlink] $targetPath -> $sourceFull (update)"
            } else {
                Write-Host "  [mkdir] $targetDir"
                Write-Host "  [symlink] $targetPath -> $sourceFull (create)"
            }
        } else {
            if ($targetDir) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            if ($exists) {
                if (Test-Path -LiteralPath $bakPath) { Remove-Item -LiteralPath $bakPath -Recurse -Force }
                Move-Item -LiteralPath $targetPath -Destination $bakPath
                Write-Host "  [backup] $targetPath -> $bakPath"
                $backedUp++
                New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourceFull | Out-Null
                Write-Host "  [symlink] $targetPath -> $sourceFull (updated)"
                $updated++
            } else {
                New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourceFull | Out-Null
                Write-Host "  [symlink] $targetPath -> $sourceFull (created)"
                $created++
            }
        }
    } elseif ($entry.method -eq 'copy') {
        $identical = $false
        if ($exists) {
            $identical = (Get-FileHash -LiteralPath $sourceFull -Algorithm MD5).Hash -eq
                         (Get-FileHash -LiteralPath $targetPath -Algorithm MD5).Hash
        }

        if ($DryRun) {
            if (-not $exists) {
                if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) { Write-Host "  [mkdir] $targetDir" }
                Write-Host "  [copy] $targetPath <- $sourceFull (create)"
            } elseif ($identical) {
                Write-Host "  [skip] $targetPath (identical)"
            } else {
                Write-Host "  [copy] $targetPath <- $sourceFull (would prompt to overwrite)"
            }
        } else {
            if (-not $exists) {
                if ($targetDir) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                Copy-Item -LiteralPath $sourceFull -Destination $targetPath
                Write-Host "  [copy] $targetPath (created)"
                $created++
            } elseif ($identical) {
                Write-Host "  [skip] $targetPath (identical)"
                $skipped++
            } else {
                Write-Host "  [diff] $targetPath differs from $sourceFull"
                $answer = Read-Host "  Overwrite $targetPath? [O]verwrite / [S]kip"
                if ($answer -match '^[Oo]') {
                    if (Test-Path -LiteralPath $bakPath) { Remove-Item -LiteralPath $bakPath -Force }
                    Move-Item -LiteralPath $targetPath -Destination $bakPath
                    Write-Host "  [backup] $targetPath -> $bakPath"
                    $backedUp++
                    Copy-Item -LiteralPath $sourceFull -Destination $targetPath
                    Write-Host "  [copy] $targetPath (updated)"
                    $updated++
                } else {
                    Write-Host "  [skip] $targetPath (user skipped)"
                    $skipped++
                }
            }
        }
    }
}

Write-Host ''
if ($DryRun) {
    Write-Host '[DRY RUN] Summary of planned actions above. No changes were made.'
} else {
    Write-Host "Done. Created: $created, Updated: $updated, Skipped: $skipped, Backed up: $backedUp"
}
