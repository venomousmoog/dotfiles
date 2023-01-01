if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
 if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
  $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments

  if (Test-Path ($pshome + "\pwsh.exe")) {
    $psexe = $pshome + "\pwsh.exe"
  } else {
    $psexe = $pshome + "\powershell.exe"
  }

  Start-Process -FilePath $psexe -Verb Runas -ArgumentList $CommandLine
  Exit
 }
}

$dotfiles = Join-Path $PSScriptRoot ..

# powershell modules
Install-Module @(
    "posh-docker"
    "posh-dotnet"
    # "posh-git"
    "posh-vs"
    # "Terminal-Icons"
    "z"
)

# winget installed tools
@(
    "7zip.7zip"
    "Docker.DockerDesktop"
    "Git.Git"
    "GitHub.cli"
    "GitHub.GitLFS"
    "Google.Chrome"
    "Google.Drive"
    "JanDeDobbeleer.OhMyPosh"
    "Microsoft.OneDrive"
    "Microsoft.PowerShell.Preview"
    "Microsoft.VisualStudio.2022.Professional"
    "Microsoft.VisualStudioCode.Insiders"
    "Microsoft.WindowsTerminal.Preview"
    "OBSProject.OBSStudio"
    "OpenJS.NodeJS.LTS"
    "OpenWhisperSystems.Signal"
    "WinMerge.WinMerge"
) | ForEach-Object {winget install "$_"}

# configuration links mapping
$links = @{
    "$Profile" = "./powershell/profile.ps1"
    "${env:APPDATA}/Code - Insiders/settings.json" = './vscode/settings.json'
    "${$env:USERPROFILE}/.gitconfig" = './git/gitconfig'
    "${env:LOCALAPPDATA}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" = './terminal/settings.json'
}

# TODO - install fonts

Set-Location $dotfiles

foreach ($k in $links.Keys) {
    Remove-Item $k
    New-Item -ItemType SymbolicLink -Path $k -Target $links[$k]
}
