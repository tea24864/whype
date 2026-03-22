@echo off
:: install_vllm.bat
:: Installs vLLM inside WSL2 (required — vLLM does not support native Windows).
:: Creates an isolated venv at ~/whype-vllm inside your default WSL distro.
:: The server still exposes http://localhost:8000 to Windows via WSL2 networking.

setlocal EnableDelayedExpansion

echo ============================================================
echo  Whype - vLLM Setup (via WSL2)
echo ============================================================
echo.

:: ── 1. Check WSL ──────────────────────────────────────────────────────────────
echo [1/4] Checking WSL2...
wsl --status >nul 2>&1
if errorlevel 1 (
    echo [ERROR] WSL is not installed or not running.
    echo         Enable it with:  wsl --install
    echo         Then reboot and re-run this script.
    pause
    exit /b 1
)
echo [OK] WSL available.
echo.

:: ── 2. Install uv inside WSL ──────────────────────────────────────────────────
echo [2/4] Installing uv inside WSL (skipped if already present)...
wsl -- bash -c "command -v ~/.local/bin/uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh"
if errorlevel 1 (
    echo [ERROR] uv installation inside WSL failed. Check output above.
    pause
    exit /b 1
)
echo [OK] uv ready.
echo.

:: ── 3. Create venv + install vLLM ────────────────────────────────────────────
echo [3/4] Creating ~/whype-vllm and installing vLLM (this may take several minutes)...
wsl -- bash -c "~/.local/bin/uv venv ~/whype-vllm --python 3.12 && ~/.local/bin/uv pip install vllm --python ~/whype-vllm/bin/python"
if errorlevel 1 (
    echo [ERROR] vLLM installation inside WSL failed. Check output above.
    pause
    exit /b 1
)
echo [OK] vLLM installed at ~/whype-vllm.
echo.

:: ── 4. Verify ─────────────────────────────────────────────────────────────────
echo [4/4] Verifying vLLM install...
wsl -- bash -c "~/whype-vllm/bin/python -c 'import vllm, torch; print(\"  vLLM version :\", vllm.__version__); print(\"  CUDA available:\", torch.cuda.is_available()); print(\"  GPU           :\", torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"NOT FOUND\")'"

echo.
echo ============================================================
echo  vLLM setup complete!
echo.
echo  Start the vLLM server:
echo    start_vllm.bat
echo.
echo  Then start Whype:
echo    start_whype.bat
echo.
echo  The first server start downloads the model weights.
echo  Subsequent starts load from the HuggingFace cache
echo  (~/.cache/huggingface inside WSL).
echo ============================================================
echo.
pause
