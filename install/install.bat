@echo off
setlocal

rem Resolve dotfiles root (parent of the install\ directory this script lives in)
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "DOTFILES_ROOT=%CD%"
popd

rem Check for nushell
where nu >nul 2>&1
if errorlevel 1 (
    echo Error: nushell ^(nu^) is not installed or not in PATH.
    echo.
    echo Install nushell:
    echo   winget install nushell
    echo   OR https://www.nushell.sh/book/installation.html
    echo.
    exit /b 1
)

nu "%DOTFILES_ROOT%\install\install.nu" %*
