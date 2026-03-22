@echo off
:: start_vllm.bat
:: Launches a local vLLM OpenAI-compatible server inside WSL2 for Whype's
:: AI cleanup feature. The server is accessible from Windows at localhost:8000.
:: Keep this window open while using Whype.

setlocal

:: ── Configurable ──────────────────────────────────────────────────────────────
:: Change MODEL to any HuggingFace model ID that fits in your VRAM.
::
::  Recommended models for RTX 4090 (24 GB VRAM, ~14 GB free after Whisper):
::    Qwen/Qwen3.5-4B                            ~8 GB   fast, great quality
::    Qwen/Qwen2.5-7B-Instruct                   ~14 GB  great quality
::    mistralai/Mistral-7B-Instruct-v0.3         ~14 GB  great quality
::    microsoft/Phi-3-mini-4k-instruct            ~8 GB   fast, good quality
::    google/gemma-2-2b-it                        ~5 GB   very fast

set MODEL=Qwen/Qwen3.5-4B
set HOST=0.0.0.0
set PORT=8000
set MAX_MODEL_LEN=4096
set GPU_MEMORY_UTILIZATION=0.50

:: ─────────────────────────────────────────────────────────────────────────────

echo ============================================================
echo  Whype vLLM Server (WSL2)
echo  Model : %MODEL%
echo  URL   : http://localhost:%PORT%
echo ============================================================
echo.

:: Check WSL venv exists
wsl -- bash -c "test -f ~/whype-vllm/bin/python" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] vLLM WSL environment not found at ~/whype-vllm.
    echo Run install_vllm.bat first.
    pause
    exit /b 1
)

echo Starting vLLM server inside WSL2...
echo (First run will download the model weights - this may take a few minutes)
echo.

wsl -- bash -c "~/whype-vllm/bin/python -m vllm.entrypoints.openai.api_server --model %MODEL% --host %HOST% --port %PORT% --max-model-len %MAX_MODEL_LEN% --gpu-memory-utilization %GPU_MEMORY_UTILIZATION% --dtype auto"

echo.
echo vLLM server exited.
pause
