$dotfiles = Join-Path $PSScriptRoot ..

# configuration links mapping
$links = @{
    "$Profile" = "./powershell/profile.ps1"
    "${env:APPDATA}/Code - Insiders/settings.json" = './vscode/settings.json'
    "${env:APPDATA}/Code - Insiders/User/settings.json" = './vscode/settings.json'
    "${env:USERPROFILE}/.gitconfig" = './git/gitconfig'
    "${env:LOCALAPPDATA}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" = './terminal/settings.json'
    "${env:APPDATA}\VS Code @ FB - Insiders\User\settings.json" = './vsc-meta/settings.json'
    "${env:APPDATA}\VS Code @ FB - Dev\User\settings.json" = './vsc-meta/settings.json'
}

# TODO - install fonts

Set-Location $dotfiles

foreach ($k in $links.Keys) {
    Remove-Item $k
    $target = Resolve-Path $links[$k]
    New-Item -ItemType SymbolicLink -Path $k -Target $target
}
