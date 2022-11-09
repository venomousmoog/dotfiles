# figure out our real profile path (in case we were invoked through a symlink?)
$scriptFile = Join-Path $PSScriptRoot $MyInvocation.MyCommand.

while ($null -ne (Get-Item $scriptFile).LinkType) {
    $scriptFile = (Get-Item $scriptFile).LinkTarget
}
$scriptPath = Split-Path $scriptFile
Write-Host "profile from $scriptFile"

# add a roaming modules path
$env:PSModulePath += [System.IO.Path]::PathSeparator + "$($scriptPath)/Modules"

# add a custom prompt
Import-Module posh-git
$GitPromptSettings.DefaultPromptPath.ForegroundColor = "Orange"
$GitPromptSettings.DefaultPromptWriteStatusFirst = $True
$GitPromptSettings.EnableFileStatus = $False
$GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true

# customize directory listing colors
$PSStyle.FileInfo.Directory = $PSStyle.Foreground.BrightMagenta

$env:VIRTUAL_ENV_DISABLE_PROMPT=1

# oh-my-posh prompt
oh-my-posh init pwsh --config "$scriptPath/ddriver.omp.json" | Invoke-Expression
Import-Module z

# terminal-icons setup
Import-Module Terminal-Icons
Add-TerminalIconsColorTheme "$scriptPath/ddriver.theme.psd1"
Set-TerminalIconsTheme -ColorTheme ddriver
Update-FormatData -Prepend "$scriptPath/listings.format.ps1xml"

# additional completion
Import-Module posh-dotnet
Import-Module posh-docker
Import-Module posh-vs

# add tools to path:
$env:PATH += [System.IO.Path]::PathSeparator + "$($scriptPath)/Tools/$($PSVersionTable.Platform)"
$env:PATH += [System.IO.Path]::PathSeparator + "$env:LOCALAPPDATA/Programs/WinMerge"
Import-Module PSfzf

# old-style listing colorization
@('.py', '.js', '.cpp', '.cc', '.html', '.json', '.md', '.cs') |
    Foreach-Object {
        $PSStyle.FileInfo.Extension[$_] = $PSStyle.Foreground.Cyan
    }
@('.mpg', '.mpeg', '.jpg', '.jpeg', '.png', '.wav') |
    Foreach-Object {
        $PSStyle.FileInfo.Extension[$_] = $PSStyle.Foreground.Yellow
    }

function Get-FileInfoStyle([System.IO.FileSystemInfo]$fsi) {
    if ($fsi -is [System.IO.DirectoryInfo]) {
        return $PSStyle.FileInfo.Directory
    }
    elseif ($fsi -is [System.IO.FileInfo]) {
        $executable = @()
        if ($env:PATHEXT) {
            $executable = ($env:PATHEXT).Split(';')
        }
        elseif ($fsi.UnixFileMode -band ([System.IO.UnixFileMode]::OtherExecute -bor [System.IO.UnixFileMode]::OtherExecute -bor [System.IO.UnixFileMode]::OtherExecute)) {
            return $PSStyle.FileInfo.Executable
        }

        $fi = [system.IO.FileInfo]$fsi
        if ([bool]($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            return $PSStyle.FileInfo.SymbolicLink
        }

        switch ($fi.Extension) {
            { $PSStyle.FileInfo.Extension.ContainsKey($_) } {
                return $PSStyle.FileInfo.Extension[$_]
            }
            { $executable -contains $_ } {
                return $PSStyle.FileInfo.Executable
            }
            default { return "" }
        }
    }
    else {
        return ""
    }
}

function Format-Listing {
    $a = $false
    $l = $false
    $aa = $false
    $r = $false
    if (($args.Length -gt 0) -and ($args[0].StartsWith("-"))) {
        $a = $args[0].Contains("a")
        $l = $args[0].Contains("l")
        $aa = $args[0].Contains("A")
        $r = $args[0].Contains("R") -or $args[0].Contains("r")
        $rest = $args[1..$args.Length]
    }
    else {
        $rest = $args
    }


    $extra = @{}
    $format = @{}
    if ($r) {
        $extra += @{Recurse = $true}
        $format = @{View = "ListingChildren"}
    }
    else {
        $format = @{View = "ListingChildrenUngrouped"}
    }
    if ($aa) {
        $extra += @{Attributes = "Hidden, !Hidden"}
    }
    $files = Get-ChildItem @extra @rest

    if (-not $a -and -not $aa) {
        $files = $files | Where-Object { -not $_.Name.StartsWith('.') }
    }

    if ($l) {
        $files | Format-Table @format
    } else {
        $files | Format-Wide -AutoSize @format
    }
}
Set-Alias -Name ls -Value Format-Listing -Option AllScope

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

$env:FBCodeRoot = "C:\open\f"
$env:PersonalScriptsRoot = $env:FBCodeRoot + "\arvr\scripts\ddriver"

function bb { python3 $env:PersonalScriptsRoot\b.py build @args }
function br { python3 $env:PersonalScriptsRoot\b.py run @args }
function bt { python3 $env:PersonalScriptsRoot\b.py test @args }
function bq { python3 $env:PersonalScriptsRoot\b.py query @args }
function bg { python3 $env:PersonalScriptsRoot\b.py targets @args }
function bd { python3 $env:PersonalScriptsRoot\b.py debug @args }
function bbq { python3 $env:PersonalScriptsRoot\b.py buildq @args }
function brq { python3 $env:PersonalScriptsRoot\b.py runq @args }
function btq { python3 $env:PersonalScriptsRoot\b.py testq @args }
function bdq { python3 $env:PersonalScriptsRoot\b.py debugq @args }
function bgq { python3 $env:PersonalScriptsRoot\b.py targetsq @args }
function b { python3 $env:PersonalScriptsRoot\b.py @args }
function udpb { python3 $env:PersonalScriptsRoot\update_compilation_database.py @args }
function tidy { python3 $env:PersonalScriptsRoot\run_clang_tidy.py @args }
function bmode([string]$mode) { $env:BUCK_MODE = "@" + $mode }
function cdba { Push-Location ($env:FBCodeRoot + "\arvr\projects\barometer") }

$LocationShortcuts = @{
    "ba" = ($env:FBCodeRoot + "\arvr\projects\barometer");
    "sc" = ($env:FBCodeRoot + "\arvr\scripts\ddriver");
    "pi" = ($env:FBCodeRoot + "\arvr\projects\pi");
}
$ShortcutLocationCompleter = {
    param($commandName, $parameterName, $stringMatch)

    $LocationShortcuts.Keys | Where-Object { $_ -match $stringMatch }
}
function Add-ShortcutLocation {
    [CmdletBinding()]
    Param
    (
        [parameter(mandatory = $true, position = 0)][string]$Name,
        [parameter(mandatory = $true, position = 0)][string]$Location
    )

    Push-Location $LocationShortcuts[$Location]
}
Register-ArgumentCompleter -CommandName Set-ShortcutLocation -ParameterName Location -ScriptBlock $ShortcutLocationCompleter
function Set-ShortcutLocation {
    [CmdletBinding()]
    Param
    (
        [parameter(mandatory = $true, position = 0)][string]$Location
    )

    Push-Location $LocationShortcuts[$Location]
}
Register-ArgumentCompleter -CommandName Set-ShortcutLocation -ParameterName Location -ScriptBlock $ShortcutLocationCompleter
Set-Alias -Name cds -Value Set-ShortcutLocation -Option AllScope

function Format-Bytes($num)
{
    $suffix = "bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"
    $index = 0
    while ($num -gt 1kb)
    {
        $num = $num / 1kb
        $index++
    }

    if ($index -eq 0) {
        return "{0:N0} {1}" -f $num, $suffix[$index]
    } else {
        return "{0:N1} {1}" -f $num, $suffix[$index]
    }
}

class DiskSpaceValue : System.IComparable
{
    [int64]$Value
    [string]$Friendly

    DiskSpaceValue($value) {
        $this.Value = [int64]$value;
        $this.Friendly = Format-Bytes($this.Value)
    }

    [int] CompareTo([object] $obj)
    {
        if ($null -eq $obj)
        {
            return 1;
        }

        if ($obj -isnot [DiskSpaceValue])
        {
            Write-Host ($obj.ToString() + "not comparable to " + $this.ToString())
            Throw ($obj.ToString() + "not comparable to " + $this.ToString())
        }
        Write-Host ("comparing " + $this.Friendly + " to " + $obj.Friendly)

        $result = switch ($this.Value - $obj.Value)
        {
            { $_ -gt 0 } { 1 }
            { $_ -lt 0 } { -1 }
            default { 0 }
        }
        return $result
    }

    [string]ToString()
    {
        return $this.Friendly
    }
}

function Get-DirectorySummary($dir = ".")
{
    get-childitem $dir |
        ForEach-Object {
            $f = $_ ;
            get-childitem -r $_.FullName |
                measure-object -property length -sum |
                Select-Object @{Name = "Name"; Expression = { $f } },
                              @{Name = "Sum"; Expression = { [DiskSpaceValue]::new($_.Sum) } }
        }
}
Set-Alias -Name du -Value Get-DirectorySummary -Option AllScope

function Get-DiskFreeSummary
{
    Get-Volume |
        ForEach-Object  {
            [PSCustomObject]@{
                "Drive" = $_.DriveLetter;
                "Total Size" = [DiskSpaceValue]::new($_.Size);
                "Space Remaining" = [DiskSpaceValue]::new($_.SizeRemaining);
            }
        } |
        Format-Table -AutoSize
}
Set-Alias -Name df -Value Get-DiskFreeSummary -Option AllScope

function windiff { winmergeu -r -u -e @args }

Update-FormatData -PrependPath $scriptPath\PathInfo.ps1xml
Update-FormatData -AppendPath $scriptPath\df.ps1xml

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
