@echo off
:: ============================================================================
:: HorizonDocTool.bat — Launcher for HorizonDocTool.ps1
:: Starts the tool with the bundled PowerShell 7 portable as Administrator.
:: Double-click this file to launch.
:: ============================================================================

setlocal

:: Resolve the directory this batch file lives in (handles spaces in path)
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PWSH=%SCRIPT_DIR%\Tools\PowerShell-7.6.0-win-x64\pwsh.exe"
set "PS1=%SCRIPT_DIR%\HorizonDocTool.ps1"

:: Check if pwsh.exe exists
if not exist "%PWSH%" (
    echo ERROR: PowerShell 7 not found at:
    echo   %PWSH%
    echo.
    echo Please make sure the portable PowerShell 7 is located at:
    echo   Tools\PowerShell-7.6.0-win-x64\pwsh.exe
    pause
    exit /b 1
)

:: Check if already running as Administrator
net session >nul 2>&1
if %errorlevel% == 0 goto :run_as_admin

:: Not admin — re-launch self elevated via PowerShell runas
:: Use the bundled pwsh.exe for the elevation call too
"%PWSH%" -NoProfile -Command ^
    "Start-Process -FilePath '%PWSH%' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%PS1%""' -Verb RunAs"
exit /b

:run_as_admin
:: Already admin — start the tool directly
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
endlocal
