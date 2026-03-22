@echo off
:: debug_whype.bat
:: Runs Whype in a visible console window so you can see all output.
:: Use this for troubleshooting.

setlocal
set SCRIPT_DIR=%~dp0

if not exist "%SCRIPT_DIR%.venv\Scripts\python.exe" (
    echo [ERROR] Virtual environment not found. Run install.bat first.
    pause
    exit /b 1
)

echo ── Whype (debug mode) ──────────────────────────────
echo Running with: %SCRIPT_DIR%.venv\Scripts\python.exe
echo.
"%SCRIPT_DIR%.venv\Scripts\python.exe" "%SCRIPT_DIR%flow.py"
echo.
echo Whype exited.
pause
