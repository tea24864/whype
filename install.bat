@echo off
setlocal EnableDelayedExpansion

echo ============================================================
echo  Whype - Setup (uv + RTX 4090)
echo ============================================================
echo.

:: ── 1. Check / install uv ────────────────────────────────────────────────────
where uv >nul 2>&1
if errorlevel 1 (
    echo [1/5] uv not found - installing via PowerShell...
    powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
    if errorlevel 1 (
        echo [ERROR] Failed to install uv. 
        echo Please install manually: https://docs.astral.sh/uv/getting-started/installation/
        pause
        exit /b 1
    )
    :: Reload PATH so uv is found in this session
    for /f "tokens=*" %%i in ('powershell -Command "[System.Environment]::GetEnvironmentVariable(\"PATH\",\"User\")"') do set "PATH=%%i;%PATH%"
) else (
    echo [1/5] uv already installed - skipping.
)

:: Confirm uv is now on PATH
where uv >nul 2>&1
if errorlevel 1 (
    echo [ERROR] uv still not on PATH after install.
    echo Please open a new terminal and re-run this script, or add uv to PATH manually.
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('uv --version') do echo [OK] %%v

echo.

:: ── 2. Create virtualenv pinned to Python 3.12 ───────────────────────────────
echo [2/5] Creating virtual environment (.venv) with Python 3.12...
uv venv .venv --python 3.12
if errorlevel 1 (
    echo.
    echo [ERROR] Could not create venv with Python 3.12.
    echo uv will try to download Python 3.12 automatically if it is not installed.
    echo If this fails, install Python 3.12 from: https://www.python.org/downloads/release/python-3120/
    pause
    exit /b 1
)
echo [OK] Virtual environment created at .venv\

echo.

:: ── 3. Install PyTorch CUDA 12.4 directly into venv ─────────────────────────
echo [3/5] Installing PyTorch 2.4 + CUDA 12.4 (RTX 4090)...
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python .venv\Scripts\python.exe
if errorlevel 1 (
    echo [WARN] CUDA 12.4 build failed - trying CUDA 12.1...
    uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 --python .venv\Scripts\python.exe
    if errorlevel 1 (
        echo [ERROR] Could not install PyTorch. Check your internet connection and try again.
        pause
        exit /b 1
    )
)
echo [OK] PyTorch installed.

echo.

:: ── 4. Install remaining deps from pyproject.toml ───────────────────────────
echo [4/5] Installing remaining dependencies...
uv pip install . --python .venv\Scripts\python.exe
if errorlevel 1 (
    echo [ERROR] Dependency installation failed.
    pause
    exit /b 1
)
echo [OK] Dependencies installed.

echo.

:: ── 5. Verify CUDA ───────────────────────────────────────────────────────────
echo [5/5] Verifying CUDA / GPU...
.venv\Scripts\python.exe -c ^
  "import torch; v=torch.__version__; c=torch.cuda.is_available(); g=torch.cuda.get_device_name(0) if c else 'NOT DETECTED'; print(f'  PyTorch : {v}'); print(f'  CUDA    : {c}'); print(f'  GPU     : {g}')"

if errorlevel 1 (
    echo [ERROR] Python verification failed - check output above.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Setup complete!
echo.
echo  To configure your vllm (enables AI cleanup):
echo    Edit: %USERPROFILE%\.whype\config.json
echo.
echo  Launch Whype:
echo    start_whype.bat
echo.
echo  The first launch downloads Whisper large-v3 (~3 GB, once only).
echo ============================================================
echo.
pause
