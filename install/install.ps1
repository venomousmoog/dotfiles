
$dotfiles = Join-Path $PSScriptRoot ..


# configuration links mapping
$links = @{
    "$Profile" = "./powershell/profile.ps1"
    "${env:APPDATA}/Code - Insiders/settings.json" = './vscode/settings.json'
    "${env:APPDATA}/Code - Insiders/User/settings.json" = './vscode/settings.json'
    "${env:USERPROFILE}/.gitconfig" = './git/gitconfig'
    "${env:LOCALAPPDATA}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" = './terminal/settings.json'
    "${env:APPDATA}\VS Code @ FB - Dev\User\settings.json" = './vsc-meta/settings.json'
}

# TODO - install fonts

Set-Location $dotfiles

foreach ($k in $links.Keys) {
    if (Test-Path $k) {
        Remove-Item $k
    }
    $target = Resolve-Path $links[$k]
    Write-Host "Linking $k to $target"
    New-Item -Force -ItemType SymbolicLink -Path $k -Target $target
}
