@echo off
setlocal

rem Resolve dotfiles root (parent of the install\ directory this script lives in)
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "DOTFILES_ROOT=%CD%"
popd

rem Check for PowerShell
where pwsh >nul 2>&1
if errorlevel 1 (
    echo Error: PowerShell ^(pwsh^) is not installed or not in PATH.
    echo.
    echo Install PowerShell:
    echo   winget install Microsoft.PowerShell
    echo   OR https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
    echo.
    exit /b 1
)

pwsh -NoProfile -File "%DOTFILES_ROOT%\install\install.ps1" %*
