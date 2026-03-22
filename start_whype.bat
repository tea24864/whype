@echo off
:: Whype Launcher
:: Runs flow.py inside the local .venv created by install.bat

setlocal

set SCRIPT_DIR=%~dp0

:: Check venv exists
if not exist "%SCRIPT_DIR%.venv\Scripts\python.exe" (
    echo [ERROR] Virtual environment not found.
    echo Please run install.bat first.
    pause
    exit /b 1
)

echo Starting Whype...
start "Whype Dictation" /min "%SCRIPT_DIR%.venv\Scripts\pythonw.exe" "%SCRIPT_DIR%flow.py"

echo Whype is running.
echo Look for the blue circle in your system tray (bottom-right).
echo Right-click it to access settings or quit.
timeout /t 3 >nul
