# figure out our real profile path (in case we were invoked through a symlink?)
$scriptFile = $PSCommandPath
$PSNativeCommandUseErrorActionPreference = $false

# Encoding to deal with changes of PowerShell 7.4
[Console]::OutputEncoding = [Text.Encoding]::UTF8

while ($null -ne (Get-Item $scriptFile).LinkType) {
    $scriptFile = (Get-Item $scriptFile).LinkTarget
}
$scriptPath = Split-Path $scriptFile
$dotfilesPath = Split-Path -Parent $scriptPath
Write-Output "profile from $scriptFile"

# helper to figure out what commands might be installed
function Test-CommandExists {
    param ($command)
    try { if (Get-Command $command -ErrorAction 'stop') { return $true } }
    catch { return $false }
}

# add a roaming modules path
$env:PSModulePath += [System.IO.Path]::PathSeparator + "$($scriptPath)/Modules"

# platform paths:
if ($IsWindows) {
    $platformName = 'Win32NT'
}
if ($IsLinux) {
    $platformName = 'Unix'
}
if ($IsMacOS) {
    $platformName = 'MacOS'
}

function Add-To-Path {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathToAdd
    )

    if ([string]::IsNullOrWhiteSpace($PathToAdd)) { return }

    $normalized = $PathToAdd.Trim()

    # Skip unresolved env-var style entries (e.g. empty OneDriveConsumer on non-Windows)
    if ($normalized -match '^\$\(.*\)$') { return }

    # Only add existing paths, and avoid duplicates. A missing path is expected
    # for these best-effort adds (platform Tools dir, empty OneDrive on macOS,
    # etc.), so note it verbosely instead of warning on every startup.
    if (-not (Test-Path -LiteralPath $normalized)) {
        Write-Verbose "Add-To-Path: path not found: $normalized"
        return
    }

    $current = @()
    if (-not [string]::IsNullOrEmpty($env:PATH)) {
        $current = $env:PATH -split [System.IO.Path]::PathSeparator
    }

    if ($normalized -notin $current) {
        $env:PATH = if ($current.Count -gt 0) {
            $env:PATH + [System.IO.Path]::PathSeparator + $normalized
        } else {
            $normalized
        }
    }
}

# add tools to path:
Add-To-Path "$($scriptPath)/Tools/$($platformName)"
Add-To-Path "$($env:OneDriveConsumer)/Tools"

if ($IsWindows) {
    Add-To-Path "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\"
    Add-To-Path "$($env:LOCALAPPDATA)\Programs\WinMerge"
    Add-To-Path "$($env:LOCALAPPDATA)\Android\sdk\platform-tools\"
    Add-To-Path "$($env:OneDriveConsumer)\tools\platform-tools\"
    Add-To-Path "$($env:OneDriveConsumer)\tools\"
}
if ($IsMacOS) {
    $(/opt/homebrew/bin/brew shellenv) | Invoke-Expression
    Add-To-Path '/Users/ddriver/Library/Android/sdk/platform-tools/'
    Add-To-Path ~/.cargo/bin
}
if ($IsLinux) {
    Add-To-Path '/packages/adb/latest/'
    Add-To-Path "$($dotfilesPath)/scripts"
    Add-To-Path ~/.agent-conductor/default/bin
}


# disable python virtual environment prompt support (we get this from oh-my-posh)
$env:VIRTUAL_ENV_DISABLE_PROMPT = 1

# oh-my-posh prompt
oh-my-posh init pwsh --config "$scriptPath/ddriver.omp.json" | Invoke-Expression

# terminal-icons setup
Import-Module Terminal-Icons
Add-TerminalIconsColorTheme "$scriptPath/ddriver.theme.psd1"
Set-TerminalIconsTheme -ColorTheme ddriver

# helper to figure out what commands might be installed
function Test-CommandExists {
    param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = ‘stop’
    try { if (Get-Command $command) { return $true } }
    catch { return $false }
    finally { $ErrorActionPreference = $oldPreference }
}

# configure bat styles and point less to it
if (Test-CommandExists 'bat') {
    Set-Alias -Name less -Value bat -Option AllScope
}

# additional tools and modules
Import-Module z
Import-Module posh-git
Import-Module posh-dotnet
Import-Module posh-docker
Import-Module posh-vs
Import-Module PSfzf
Import-Module "$scriptPath\Modules\PSBashCompletions"
Import-Module "$scriptPath\listing.ps1"
if ($IsWindows) {
    Import-Module "$scriptPath\disk-usage.ps1"
}
Import-Module "$scriptPath\posh-buck.ps1"

function Find-CommandLocation([String]$command) {
    $paths = ($env:PATH).Split(':')
    $found = foreach ($path in $paths) {
        $testPath = Join-Path $path $command
        if (Test-Path $testPath) {
            $testPath
        }
    }
    $found
}

function Get-CommandLocation {
    $cmd = (Get-Command @args -ErrorAction Ignore)
    if (-not $cmd) {
        Write-Error -Message "'$args' not found." -Category ObjectNotFound
    } else {
        $path = if ($cmd.Source) {
            $cmd.Source
        } elseif ($cmd.DisplayName) {
            $cmd.DisplayName
        } elseif ($cmd.Name) {
            $cmd.Name
        }
        $alt = (Find-CommandLocation @args) | Where-Object { $_ -ne $path }

        @($path) + $alt
    }
}
if (Test-Path alias:where) {
    Remove-Item alias:where -Force
}
Set-Alias -Name where -Value Get-CommandLocation -Option AllScope
Set-Alias -Name which -Value Get-CommandLocation -Option AllScope

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Add a helper to shorten 'missing command' messages
$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param($Name, [System.Management.Automation.CommandLookupEventArgs]$CommandLookupArgs)

    $Trimmed = $Name
    if ($Name.StartsWith('get-')) {
        $Trimmed = $Name.Substring(4)
    }

    # Check if command was directly invoked by user
    # For a command invoked by a running script, CommandOrigin would be `Internal`
    if ($CommandLookupArgs.CommandOrigin -eq 'Runspace') {
        # Assign a new action scriptblock, close over $Name from this scope
        $CommandLookupArgs.CommandScriptBlock = {
            Write-Error -Message "'$Trimmed' not found." -Category ObjectNotFound -CategoryActivity 'command'
        }.GetNewClosure()
    }
}

if (-not (Get-Command 'sudo' -ErrorAction Ignore)) {
    function sudo {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true, position = 0)][string]$Command,
            [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)]$Remaining
        )
        Start-Process $Command -Verb RunAs -ArgumentList "$($Remaining)"
    }
}

if (-not (Test-Path env:USERNAME)) {
    $env:USERNAME = $env:USER
}
Set-PSReadLineOption -EditMode Windows

# alias winmerge to windiff because I can never remember these are
function windiff { winmergeu -r -u -e @args }

function Set-VirtualEnvironment($dir = (Get-Location)) {
    $item = [System.IO.DirectoryInfo](Get-Item $dir)

    while ($item) {
        if (Test-Path -Path ($item.FullName + '/.venv')) {
            Write-Host "using environment $($item.FullName + '/.venv')"
            $path = ($item.FullName + '/.venv/Scripts/Activate.ps1')
            . $path -Prompt ($item.Parent.BaseName + '/' + $item.BaseName)
            return
        }
        $item = $item.Parent
    }
}
Set-Alias -Name venv -Value Set-VirtualEnvironment -Option AllScope

# Update VSCode environment variables from tmux and set window title
function Update-TmuxEnvironment {
    if ($env:TMUX) {
        $tmuxEnv = tmux show-environment | Where-Object { $_ -match '^(VSCODE_IPC_HOOK_CLI|VSCODE_GIT_IPC_HANDLE|VSCODE_GIT_ASKPASS_NODE|VSCODE_GIT_ASKPASS_MAIN)=' }
        foreach ($line in $tmuxEnv) {
            if ($line -match '^([^=]+)=(.*)$') {
                Set-Item -Path "env:$($matches[1])" -Value $matches[2]
            }
        }
        $title = (oh-my-posh print primary --config "$scriptPath/tmux-title.omp.json" --plain --shell pwsh --pwd $PWD).Trim()
        tmux rename-window -t $env:TMUX_PANE "$title"
    }
}
Set-Alias -Name ue -Value Update-TmuxEnvironment -Option AllScope

# links
function ln {
    param
    (
        [parameter(mandatory = $true, position = 0)]
        [ValidateScript( { if (-not (Test-Path -Path $_ ) ) { throw 'path not found' } else { $true } })]
        [System.IO.FileInfo]$File,

        [parameter(position = 1)]
        [System.IO.FileInfo]$Link = '.',

        [switch]$s
    )

    if ((Test-Path $Link) -and (Test-Path $Link -PathType Container)) {
        $Link = Join-Path $Link $File.BaseName
    }

    if ($s) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $File
    } else {
        New-Item -ItemType HardLink -Path $Link -Target $File
    }
}

function pwto {
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Command
    )

    # $Command += ' 2>&1'
    Write-Host $Command

    # $commandString = ($Command -join ' ') + " 2>&1"
    & @Command | Tee-Object -Variable displayOutput
    $displayOutput | pastry --title "$commandString"
}

# completions

# if we want native completions:
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker completion powershell | Out-String | Invoke-Expression
}
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl completion powershell | Out-String | Invoke-Expression
}
if (Get-Command podman -ErrorAction SilentlyContinue) {
    podman completion powershell | Out-String | Invoke-Expression
}

# exclusions tracks commands we've already found
$exclusions = @('docker', 'kubectl', 'podman')
$inclusions = @('docker', 'kubectl', 'podman', 'git', 'hg', 'podman', 'buck2', 'buck', 'wget')

$completion_paths = @((Join-Path -Path $scriptPath -ChildPath 'completions'), '/usr/share/bash-completion/completions')

$completion_paths |
Where-Object { Test-Path $_ } |
ForEach-Object {
    $completion_files = Get-ChildItem $_ -File
    $completion_files |
    Where-Object { $_.Name -notin $exclusions } |
    Where-Object { $_.Name -in $inclusions } |
    ForEach-Object {
        $completion_files = Get-ChildItem $_ -File
        $completion_files |
            Where-Object { $_.Name -notin $exclusions } |
            Where-Object { $_.Name -in $inclusions } |
            ForEach-Object {
                Register-BashArgumentCompleter $_.Name $_.FullName
                $exclusions += @($_)
            }
        }
    }

# Register a bash completion only when its file is actually present, so an
# optional/missing completion file doesn't throw a validation error at startup.
function Register-BashCompletionIfPresent {
    param([string]$Command, [string]$CompletionPath)
    if ($CompletionPath -and (Test-Path -LiteralPath $CompletionPath)) {
        Register-BashArgumentCompleter $Command $CompletionPath
    }
}

Register-BashCompletionIfPresent hg /etc/bash_completion.d/mercurial.sh
Register-BashCompletionIfPresent jf /etc/bash_completion.d/jf
# Register-BashCompletionIfPresent buck2 /etc/bash_completion.d/buck-fbsource.bash


function Get-ReversedHgSl {
    if ($MyInvocation.PipelinePosition -eq $MyInvocation.PipelineLength) {
        $output = & hg sl --color=always @Args
    } else {
        $output = & hg sl @Args
    }

    $lines = $output -split "`n"
    [Array]::Reverse($lines)
    $lines = $lines | ForEach-Object { $_ -replace '╯', '╮' }
    $lines = $lines | ForEach-Object { $_ -replace '╭', '╰' }
    $lines
}

Remove-Item alias:sl -Force
Set-Alias -Name sl -Value Get-ReversedHgSl -Option AllScope


# Colored grep by default (nothing else special). Resolve the real binary with
# -CommandType Application so re-sourcing the profile never picks up this wrapper
# function itself (which left $grep_path empty and broke grep). Gate on
# $MyInvocation.ExpectingInput so a plain 'grep pattern file' call runs grep
# directly instead of piping an empty $input into it and blocking on stdin.
$grepPath = (Get-Command grep -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1).Source
if ($grepPath) {
    function grep {
        if ($MyInvocation.ExpectingInput) {
            $input | & $grepPath --color=auto @Args
        } else {
            & $grepPath --color=auto @Args
        }
    }
}

# tlist: list processes / find loaded modules, à la the Windows debugger's
# 'tlist' (https://learn.microsoft.com/windows-hardware/drivers/debugger/tlist-commands).
# Windows already ships tlist.exe, so only define our shim elsewhere.
if (-not $IsWindows) {
    function tlist {
        <#
        .SYNOPSIS
            List processes / find loaded modules — a Unix & macOS take on the
            Windows debugger 'tlist' tool.
        .DESCRIPTION
            tlist                List every process (PID, PPID, name).
            tlist <pattern>      List processes whose name or command line
                                 matches <pattern> (case-insensitive regex).
            tlist --fuzzy <pat>  Fuzzy (subsequence) match over process names,
                                 fzf / VS Code style, ranked best-first (uses
                                 fzf if available). Also -f / /f.
            tlist <pid>          Show details for a PID, including its loaded
                                 modules (dylibs/.so), via lsof.
            tlist -t             Show the process tree (child under parent).
            tlist -p <name>      Print the PID(s) of processes named <name>.
            tlist -c             List every process with its full command line.
            tlist -m <module>    List processes that have <module> loaded
                                 (a dylib/.so/executable; name or regex).

            Windows-style slash flags (/t /p /c /m) work too. Without sudo the
            lsof-based views (-m and per-pid modules) only see your own
            processes, and macOS shared-cache system libs won't appear; prefix
            with sudo for a fuller, system-wide view.
        #>

        # Collect processes: two cheap ps calls joined on pid so 'comm' (which
        # may contain spaces on macOS) always parses as a clean trailing field.
        $procs = & {
            $argsMap = @{}
            foreach ($l in (& ps -axww -o pid=,args= 2>$null)) {
                if ($l -match '^\s*(\d+)\s+(.+?)\s*$') { $argsMap[[int]$matches[1]] = $matches[2] }
            }
            foreach ($l in (& ps -axww -o pid=,ppid=,comm= 2>$null)) {
                if ($l -match '^\s*(\d+)\s+(\d+)\s+(.+?)\s*$') {
                    $procPid = [int]$matches[1]
                    [pscustomobject]@{
                        PID     = $procPid
                        PPID    = [int]$matches[2]
                        Name    = Split-Path -Leaf $matches[3]
                        Path    = $matches[3]
                        Command = if ($argsMap.ContainsKey($procPid)) { $argsMap[$procPid] } else { $matches[3] }
                    }
                }
            }
        }

        # Modules loaded by a process set, via lsof field output. txt = the
        # executable itself, mem = memory-mapped libraries, DEL = mapped but
        # unlinked; that trio is what "has module loaded" means on Unix.
        function Get-Modules {
            param([string[]]$LsofArgs, [string]$NamePattern)
            $curPid = $null; $curCmd = $null; $curFd = $null
            foreach ($line in (& lsof -w -n -P -F pcfn @LsofArgs 2>$null)) {
                if ($line.Length -lt 1) { continue }
                $val = $line.Substring(1)
                switch ($line[0]) {
                    'p' { $curPid = [int]$val }
                    'c' { $curCmd = $val }
                    'f' { $curFd = $val }
                    'n' {
                        if ($curFd -match '^(txt|mem|DEL)') {
                            if (-not $NamePattern -or $val -match $NamePattern) {
                                [pscustomobject]@{ PID = $curPid; Command = $curCmd; FD = $curFd; Module = $val }
                            }
                        }
                    }
                }
            }
        }

        # Fuzzy (subsequence) score, à la fzf / VS Code: query chars must appear
        # in order; reward contiguous runs, word boundaries and camelCase humps;
        # smart-case (case-insensitive unless the query has an uppercase letter).
        # Returns $null when the query isn't a subsequence of the target.
        function Get-FuzzyScore {
            param([string]$Query, [string]$Target)
            if ([string]::IsNullOrEmpty($Query)) { return 0 }
            $t = $Target
            if ($Query -cnotmatch '[A-Z]') { $t = $Target.ToLower() }   # smart-case
            $seps = '/-_. \'
            $ti = 0; $score = 0; $streak = 0; $first = -1
            foreach ($qc in $Query.ToCharArray()) {
                $found = $false
                while ($ti -lt $t.Length) {
                    if ($t[$ti] -eq $qc) {
                        if ($first -lt 0) { $first = $ti }
                        $streak++
                        $score += 1 + ($streak * 2)
                        if ($ti -eq 0 -or $seps.IndexOf([string]$t[$ti - 1]) -ge 0) {
                            $score += 5                                  # word boundary
                        } elseif ([char]::IsUpper($Target[$ti]) -and
                                  -not [char]::IsUpper($Target[$ti - 1])) {
                            $score += 3                                  # camelCase hump
                        }
                        $ti++; $found = $true; break
                    } else { $streak = 0; $ti++ }
                }
                if (-not $found) { return $null }
            }
            return ($score - $first)
        }

        # Fuzzy-filter objects by a query, ranked best-first. Prefers the real
        # fzf binary (matching your muscle memory exactly); falls back to the
        # scorer above when fzf isn't installed.
        function Select-Fuzzy {
            param([object[]]$Items, [scriptblock]$Text, [string]$Query)
            $Items = @($Items)
            if ([string]::IsNullOrEmpty($Query) -or $Items.Count -eq 0) { return $Items }
            $strings = foreach ($it in $Items) { (& $Text $it) -replace "`t", ' ' }
            $fzf = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue
            if ($fzf) {
                $lines = for ($i = 0; $i -lt $Items.Count; $i++) { "$i`t$($strings[$i])" }
                $ranked = $lines | & $fzf.Source --filter=$Query --delimiter="`t" --nth='2..' 2>$null
                foreach ($r in $ranked) {
                    $idx = ($r -split "`t", 2)[0] -as [int]
                    if ($null -ne $idx -and $idx -ge 0 -and $idx -lt $Items.Count) { $Items[$idx] }
                }
            } else {
                $scored = for ($i = 0; $i -lt $Items.Count; $i++) {
                    $s = Get-FuzzyScore -Query $Query -Target $strings[$i]
                    if ($null -ne $s) { [pscustomobject]@{ Item = $Items[$i]; Score = $s } }
                }
                $scored | Sort-Object -Property Score -Descending | Select-Object -ExpandProperty Item
            }
        }

        $flag = $null
        if ($args.Count -gt 0 -and $args[0] -match '^[-/]+(.+)$') { $flag = $matches[1].ToLower() }

        switch ($flag) {
            't' {
                $byParent = @{}
                foreach ($p in $procs) {
                    if (-not $byParent.ContainsKey($p.PPID)) { $byParent[$p.PPID] = @() }
                    $byParent[$p.PPID] += $p
                }
                $known = @{}; foreach ($p in $procs) { $known[$p.PID] = $true }
                $seen  = [System.Collections.Generic.HashSet[int]]::new()
                $emit  = {
                    param($node, $depth)
                    if (-not $seen.Add([int]$node.PID)) { return }
                    ('  ' * $depth) + ('{0,-7} {1}' -f $node.PID, $node.Name)
                    if ($byParent.ContainsKey($node.PID)) {
                        foreach ($child in ($byParent[$node.PID] | Sort-Object PID)) { & $emit $child ($depth + 1) }
                    }
                }
                $roots = $procs | Where-Object { -not $known.ContainsKey($_.PPID) -or $_.PID -eq $_.PPID } | Sort-Object PID
                foreach ($r in $roots) { & $emit $r 0 }
                foreach ($p in ($procs | Sort-Object PID)) { if (-not $seen.Contains([int]$p.PID)) { & $emit $p 0 } }
                return
            }
            'p' {
                $name = $args[1]
                if (-not $name) { Write-Error 'tlist -p needs a process name'; return }
                # match the process NAME only (like Windows tlist /p), not the cmdline
                $hits = @($procs | Where-Object { $_.Name -match $name } |
                    Select-Object -ExpandProperty PID | Sort-Object -Unique)
                if ($hits.Count -eq 0) { -1 } else { $hits }
                return
            }
            'c' { $procs | Select-Object PID, PPID, Command; return }
            { $_ -eq 'f' -or $_ -eq 'fuzzy' } {
                # fuzzy (subsequence) match over process names, fzf/VS Code style
                Select-Fuzzy -Items $procs -Query $args[1] -Text { param($p) $p.Name } |
                    Select-Object PID, PPID, Name
                return
            }
            'm' {
                $module = $args[1]
                if (-not $module) { Write-Error 'tlist -m needs a module name/pattern'; return }
                Get-Modules -NamePattern $module | Sort-Object PID, Module -Unique |
                    Select-Object PID, Command, Module
                return
            }
            default {
                $arg0 = $args[0]
                if ($null -eq $arg0) {
                    $procs | Select-Object PID, PPID, Name
                } elseif ($arg0 -match '^\d+$') {
                    $targetPid = [int]$arg0
                    & ps -p $targetPid -o pid,ppid,user,%cpu,%mem,etime,args 2>$null
                    ''
                    'Loaded modules:'
                    Get-Modules -LsofArgs @('-p', "$targetPid") |
                        Select-Object -ExpandProperty Module -Unique | Sort-Object |
                        ForEach-Object { '  ' + $_ }
                } else {
                    $procs | Where-Object { $_.Name -match $arg0 -or $_.Command -match $arg0 } |
                        Select-Object PID, PPID, Name
                }
            }
        }
    }
}

function Debug-CoreDump {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$CoreDumpId
    )

    # Create a temporary directory and navigate to it
    $tempDir = New-Item -ItemType Directory -Path (Join-Path ($null -ne ${env:TEMP} ? $env:TEMP : '/tmp') ([System.IO.Path]::GetRandomFileName()))
    Push-Location $tempDir.FullName
    Write-Host "Working directory: $($tempDir.FullName)"

    try {
        # Download coredump
        Write-Host "Downloading coredump $CoreDumpId..."
        & coredumps get -c coredumps_default.$CoreDumpId ./$CoreDumpId

        if (-not (Test-Path "./$CoreDumpId")) {
            Write-Error "Failed to download coredump $CoreDumpId"
            return
        }

        # Launch lldb with symbol server and auto-load-debuginfo
        Write-Host "Launching lldb with symbol server and auto-load-debuginfo..."
        & lldb -c $CoreDumpId -O symsrv -o auto-load-debuginfo
    }
    finally {
        # Return to original directory
        Pop-Location
        Write-Host "Temporary directory: $($tempDir.FullName)"
        Write-Host "You may want to clean up the temporary directory when done."
    }
}

if ($env:TERM_PROGRAM -eq 'vscode') {
    $env:EDITOR="code-fb --wait"
} else {
    $env:EDITOR = 'nano'
}

# Run a command with the current Meta fwdproxy env vars set, restoring prior
# values afterward. Usage: with-fwdproxy az login
function with-fwdproxy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $configOutput = & fwdproxy-config curl --format=sh
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'fwdproxy-config failed'
        return
    }

    $vars = [ordered]@{}
    foreach ($line in $configOutput) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $value = $matches[2]
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                $value = $matches[1]
            }
            $vars[$matches[1]] = $value
        }
    }

    $previous = @{}
    foreach ($key in $vars.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key)
    }

    try {
        foreach ($key in $vars.Keys) {
            Set-Item -Path "env:$key" -Value $vars[$key]
        }
        & $Command @Arguments
    } finally {
        foreach ($key in $previous.Keys) {
            if ($null -eq $previous[$key]) {
                Remove-Item -Path "env:$key" -ErrorAction SilentlyContinue
            } else {
                Set-Item -Path "env:$key" -Value $previous[$key]
            }
        }
    }
}


$originalPromptFunction = $function:prompt
function prompt {
    # Run your tmux update script silently
    Update-TmuxEnvironment -ErrorAction SilentlyContinue

    # Call the original prompt function
    & $originalPromptFunction
}

# Alias 'cat' to 'bat' when available, falling back to system cat otherwise
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias -Name cat -Value bat -Option AllScope
} elseif (-not (Get-Alias -Name cat -ErrorAction SilentlyContinue)) {
    # Ensure 'cat' still resolves on platforms where it's not a builtin alias
    $sysCat = Get-Command cat -ErrorAction SilentlyContinue
    if ($sysCat) { Set-Alias -Name cat -Value $sysCat.Source -Option AllScope }
}

$env:CLAUDE_CODE_VERSION_OVERRIDE="latest"

function myclaw-jet {
    $old = $env:MYCLAW_HOME
    $env:MYCLAW_HOME = "$HOME\.myclaw-jet"
    try { myclaw @args } finally { $env:MYCLAW_HOME = $old }
}

function myclaw-rodan {
    $old = $env:MYCLAW_HOME
    $env:MYCLAW_HOME = "$HOME\.myclaw-rodan"
    try { myclaw @args } finally { $env:MYCLAW_HOME = $old }
}

function myclaw-king {
    $old = $env:MYCLAW_HOME
    $env:MYCLAW_HOME = "$HOME\.myclaw-king"
    try { myclaw @args } finally { $env:MYCLAW_HOME = $old }
}
