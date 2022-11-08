$dotfiles = Join-Path $PSScriptRoot ..

Install-Module @(
    "posh-vs", 
    "posh-dotnet", 
    "posh-docker"
) 

@(
    "Microsoft.VisualStudioCode.Insiders", 
    "JanDeDobbeleer.OhMyPosh"
) | ForEach-Object {winget install "$_"}


# $links = @{
#     $Profile = "./powershell/profile.ps1"
#     "${env:APPDATA}\Code - Insiders\settings.json" = './vscode/settings.json'
# }

# Set-Location $dotfiles

# foreach ($k in $links.Keys) {
#     Remove-Item $k
#     New-Item -ItemType SymbolicLink -Path $k -Target $links[$k]
# }
