# figure out our real profile path (in case we were invoked through a symlink?)
$scriptFile = $PSCommandPath
$PSNativeCommandUseErrorActionPreference = $false

# Encoding to deal with changes of PowerShell 7.4
[Console]::OutputEncoding = [Text.Encoding]::UTF8

while ($null -ne (Get-Item $scriptFile).LinkType) {
    $scriptFile = (Get-Item $scriptFile).LinkTarget
}
$scriptPath = Split-Path $scriptFile
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

# add tools to path:
$env:PATH += [System.IO.Path]::PathSeparator + "$($scriptPath)/Tools/$($platformName)"

if ($IsWindows) {
    $env:PATH += [System.IO.Path]::PathSeparator + ${Env:ProgramFiles(x86)} + '\Windows Kits\10\Debuggers\x64\'
    $env:PATH += [System.IO.Path]::PathSeparator + "$env:LOCALAPPDATA\Programs\WinMerge"
    $env:PATH += [System.IO.Path]::PathSeparator + "$env:LOCALAPPDATA\Android\sdk\platform-tools\"
}
if ($IsMacOS) {
    $(~/homebrew/bin/brew shellenv) | Invoke-Expression
    $env:PATH += [System.IO.Path]::PathSeparator + '/Users/ddriver/Library/Android/sdk/platform-tools/'
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
    $env:BAT_THEME = 'zenburn'
    $env:BAT_STYLE = 'grid,numbers'
    Set-Alias -Name less -Value bat -Option AllScope
}

# additional tools and modules
# Import-Module z
Import-Module posh-git
Import-Module posh-dotnet
Import-Module posh-docker
Import-Module posh-vs
Import-Module PSfzf
Import-Module "$scriptPath\Modules\PSBashCompletions"
Import-Module "$scriptPath\listing.ps1"
Import-Module "$scriptPath\disk-usage.ps1"
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

# completions
$native_completions = @('docker', 'kubectl')

if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker completion powershell | Out-String | Invoke-Expression
}
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl completion powershell | Out-String | Invoke-Expression
}
if (Get-Command podman -ErrorAction SilentlyContinue) {
    podman completion powershell | Out-String | Invoke-Expression
}

$completion_paths = @((Join-Path -Path $scriptPath -ChildPath 'completions'), '/usr/share/bash-completion')

$completion_paths |
Where-Object { Test-Path $_ } | 
ForEach-Object {
    $completion_files = Get-ChildItem (Join-Path -Path $scriptPath -ChildPath 'completions') -File
    $completion_files |
    Where-Object { $_.Name -notin $native_completions } |
    ForEach-Object {
        Register-BashArgumentCompleter $_.Name $_.FullName
    }
    
    $native_completions += $completion_files
}


