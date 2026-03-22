# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whype is a Windows-only, privacy-first, AI-polished voice dictation application. It transcribes speech to text using local OpenAI Whisper and optionally cleans up the text via a locally-running vLLM server. The entire application is a single file: `flow.py`.

## Setup

The main app uses a Windows venv; vLLM runs inside WSL2 to work around its Linux-only build requirement:

- `.venv/` — Main app (Whisper, sounddevice, pystray, etc.)
- `~/whype-vllm` (inside WSL2) — vLLM server only

```bat
install.bat        # Creates .venv, installs PyTorch CUDA 12.4 + dependencies
install_vllm.bat   # Installs uv + vLLM inside WSL2 at ~/whype-vllm
```

Dependencies are managed via `uv` (Astral). The project uses `pyproject.toml` but has no test suite or linter configured.

## Running

```bat
start_whype.bat   # Launch dictation app (minimized to system tray)
start_vllm.bat       # Launch vLLM server inside WSL2 (exposes localhost:8000)
debug_whype.bat   # Launch with visible console for debugging
```

Or directly:
```bash
.venv/Scripts/python flow.py
```

## Architecture

`flow.py` (~400 lines) is the entire application. Key sections:

| Lines | Component | Description |
|-------|-----------|-------------|
| 31–78 | Config | `DEFAULT_CONFIG` defaults + `CLEANUP_SYSTEM_PROMPT` constant |
| 88–105 | Config helpers | Loads/saves `~/.whype/config.json` |
| 108–131 | Transcription | Loads Whisper model (CUDA/fp16), transcribes audio |
| 134–192 | AI Cleanup | `/health` check + HTTP call to vLLM `/v1/chat/completions` |
| 195–238 | Audio | `sounddevice` callback, recording state, `process_audio` pipeline |
| 241–258 | Output | Clipboard save → Ctrl+V paste → clipboard restore |
| 261–330 | System Tray | `pystray` icon with status colours and right-click menu |
| 333–350 | Hotkey | Press/release handlers with `e.name == hk` guard |
| 353–400 | Main | Startup: config load, GPU check, vLLM ping, audio stream, tray |

**Data flow:** Hotkey press → audio stream accumulates → hotkey release → Whisper transcription → (optional) vLLM cleanup → clipboard paste into active window.

**State:** A simple boolean flag controls recording state. The Whisper model is loaded once at startup in a background thread.

**vLLM integration:** Uses stdlib `urllib` (no `requests`/`httpx`). Sends `chat_template_kwargs: {"enable_thinking": false}` to suppress Qwen3's chain-of-thought output. Falls back gracefully to raw transcript if the server is unreachable. The vLLM server runs in WSL2 but is transparently accessible at `localhost:8000` from Windows.

**Hotkey guard:** `setup_hotkey` uses `e.name == hk` inside the callback to prevent left/right modifier keys both triggering when only one side is configured.

**`CLEANUP_SYSTEM_PROMPT`** (lines 55–78) instructs the LLM to fix grammar, add punctuation, handle spoken formatting commands ("new line", "comma", etc.), and — when the input is Chinese — convert to Traditional Chinese (繁體中文).

## Configuration

Runtime config is stored at `~/.whype/config.json` (auto-created with defaults on first run):

| Key | Default | Description |
|-----|---------|-------------|
| `hotkey` | `"right ctrl"` | Global recording hotkey |
| `whisper_model` | `"large-v3"` | Whisper model size |
| `language` | `null` | Force language (e.g. `"zh"`) or auto-detect |
| `sample_rate` | `16000` | Audio capture sample rate (Hz) |
| `channels` | `1` | Audio channels |
| `min_duration` | `0.3` | Ignore recordings shorter than this (seconds) |
| `ai_cleanup` | `true` | Enable vLLM text cleanup |
| `vllm_base_url` | `"http://localhost:8000"` | vLLM server endpoint |
| `vllm_model` | `"Qwen/Qwen3.5-4B"` | HuggingFace model ID |
| `vllm_max_tokens` | `1024` | Max tokens for cleanup response |
| `vllm_timeout` | `30` | HTTP timeout for vLLM calls (seconds) |
| `output_mode` | `"type"` | Output method (only `"type"` implemented) |
