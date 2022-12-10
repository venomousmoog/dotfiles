function Invoke-Elevated {
    [CmdletBinding()]
    Param
    (
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)]$CommandLine
    )

    if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
            if (Test-Path ($pshome + '\pwsh.exe')) {
                $psexe = $pshome + '\pwsh.exe'
            } elseif (Test-Path ($pshome + '\pwsh-preview.exe')) {
                $psexe = $pshome + '\pwsh-preview.exe'
            } else {
                $psexe = $pshome + '\powershell.exe'
            }
       
            Start-Process -Wait -NoNewWindow -FilePath $psexe -Verb Runas -ArgumentList $CommandLine
        }
    }

    Start-Process -Wait -NoNewWindow -FilePath $psexe -Verb Runas -ArgumentList $CommandLine
}

function Invoke-CommandElevated {
    [CmdletBinding()]
    Param
    (
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)]$CommandLine
    )

    # build a command-line from the arguments
    $CommandLine = "-Command " + $args
       
    Invoke-PowershellElevated -Command $CommandLine 
}
Set-Alias -Name sudo -Value Invoke-CommandElevated -Option AllScope

function Invoke-ScriptElevated {
    # build a command-line from the current script:
    $CommandLine = "`"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
       
    Invoke-PowershellElevated -ScriptFile $CommandLine
}



