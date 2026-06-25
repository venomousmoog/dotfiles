
$dotfiles = Join-Path $PSScriptRoot ..


# configuration links mapping
$links = @{
    "$Profile" = "./powershell/profile.ps1"
    "${env:APPDATA}/Code - Insiders/settings.json" = './vscode/settings.json'
    "${env:APPDATA}/Code - Insiders/User/settings.json" = './vscode/settings.json'
    "${env:LOCALAPPDATA}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" = './terminal/settings.json'
    "${env:APPDATA}\VS Code @ FB - Insiders\User\settings.json" = './vsc-meta/settings.json'
    "${env:APPDATA}\VS Code @ FB - Dev\User\settings.json" = './vsc-meta/settings.json'
    "${env:USERPROFILE}/markdown-styles.css" = './docs/markdown-styles.css'
    "${env:USERPROFILE}/.vscode/markdown-styles.css" = './docs/markdown-styles.css'
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

# ~/.gitconfig must be a REAL file (not a symlink into the repo) so that tools
# running `git config --global ...` write here instead of mutating the tracked
# git/gitconfig. The local file just `[include]`s the repo gitconfig. See
# git/gitconfig.local.stub.
$gitconfig = "${env:USERPROFILE}/.gitconfig"
$repoGitconfig = (Resolve-Path './git/gitconfig').Path -replace '\\', '/'
if (Test-Path $gitconfig) { Remove-Item -Force $gitconfig }
Write-Host "Writing $gitconfig (include -> $repoGitconfig)"
Set-Content -Path $gitconfig -Value "[include]`n`tpath = $repoGitconfig"
