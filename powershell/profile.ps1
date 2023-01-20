# figure out our real profile path (in case we were invoked through a symlink?)
$scriptFile = $PSCommandPath
$PSNativeCommandUseErrorActionPreference = $false

while ($null -ne (Get-Item $scriptFile).LinkType) {
    $scriptFile = (Get-Item $scriptFile).LinkTarget
}
$scriptPath = Split-Path $scriptFile
Write-Host "profile from $scriptFile"

# add a roaming modules path
$env:PSModulePath += [System.IO.Path]::PathSeparator + "$($scriptPath)/Modules"

# disable virtual prompt support (we get this from oh-my-posh)
$env:VIRTUAL_ENV_DISABLE_PROMPT=1

# oh-my-posh prompt
oh-my-posh init pwsh --config "$scriptPath/ddriver.omp.json" | Invoke-Expression

# terminal-icons setup
Import-Module Terminal-Icons
Add-TerminalIconsColorTheme "$scriptPath/ddriver.theme.psd1"
Set-TerminalIconsTheme -ColorTheme ddriver

# add tools to path:
$env:PATH += [System.IO.Path]::PathSeparator + "$($scriptPath)/Tools/$($PSVersionTable.Platform)"
$env:PATH += [System.IO.Path]::PathSeparator + "$env:LOCALAPPDATA/Programs/WinMerge"

# configure bat styles
$env:BAT_THEME="zenburn"
$env:BAT_STYLE="grid,numbers"

# additional completion
Import-Module z
Import-Module posh-git
Import-Module posh-dotnet
Import-Module posh-docker
Import-Module posh-vs
Import-Module PSfzf
Import-Module "$scriptPath\listing.ps1"
Import-Module "$scriptPath\disk-usage.ps1"
Import-Module "$scriptPath\posh-buck.ps1"

function Get-CommandLocation {
    $path = (Get-Command @args -ErrorAction Ignore).Path
    if (!$path) {
        Write-Error -Message "'$args' not found." -Category ObjectNotFound
    }
    $path
}
if (Test-Path alias:where) {
    Remove-Item alias:where -Force
}
Set-Alias -Name where -Value Get-CommandLocation -Option AllScope
Set-Alias -Name which -Value Get-CommandLocation -Option AllScope

Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# Add a helper to shorten 'missing command' messages
$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param($Name, [System.Management.Automation.CommandLookupEventArgs]$CommandLookupArgs)

    $Trimmed = $Name
    if ($Name.StartsWith("get-")) {
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

if (-Not (Get-Command "sudo" -ErrorAction Ignore)) {
    function sudo {
        [CmdletBinding()]
        Param
        (
            [parameter(mandatory = $true, position = 0)][string]$Command,
            [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)]$Remaining
        )
        Start-Process $Command -Verb RunAs -ArgumentList "$($Remaining)"
    }
}


# alias winmerge to windiff because I can never remember these are
function windiff { winmergeu -r -u -e @args }

function Set-VirtualEnvironment($dir = (Get-Location))
{
    $item = [System.IO.DirectoryInfo](Get-Item $dir)

    while ($item) {
        if (Test-Path -Path ($item.FullName + "/.venv")) {
            Write-Host "using environment $($item.FullName + "/.venv")"
            $path = ($item.FullName + "/.venv/Scripts/Activate.ps1")
            . $path -Prompt ($item.Parent.BaseName + "/" + $item.BaseName)
            return
        }
        $item = $item.Parent
    }
}
Set-Alias -Name venv -value Set-VirtualEnvironment -Option AllScope


Set-Alias -Name less -Value bat -Option AllScope


# links
function ln
{
    Param
    (
        [parameter(mandatory = $true, position = 0)]
        [ValidateScript( { if (-Not (Test-Path -Path $_ ) ) { throw "path not found" } else { $true } })]
        [System.IO.FileInfo]$File,

        [parameter(position = 1)]
        [System.IO.FileInfo]$Link = ".",

        [switch]$s
    )

    if ((Test-Path $Link) -and (Test-Path $Link -PathType Container)) {
        $Link = Join-Path $Link $File.BaseName
    }

    if ($s) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $File
    }
    else {
        New-Item -ItemType HardLink -Path $Link -Target $File
    }
}
