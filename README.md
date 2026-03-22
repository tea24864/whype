# 🎙️ Whype

An AI-polished voice dictation app for Windows with RTX 4090.
Hold a hotkey anywhere → speak → release → AI-polished text appears in any app.

**100% local and private.** Whisper runs on your GPU for transcription.
A local vLLM server handles AI cleanup — no cloud APIs, no data leaves your machine.

---

## How it works

```
[Hold hotkey]
     │
     ▼
[Whisper large-v3]  ←── local, RTX 4090, ~200ms
     │  raw transcript
     ▼
[vLLM server]       ←── local, Qwen/Qwen3.5-4B (WSL2)
     │  cleaned text
     ▼
[Ctrl+V into active window]
```

---

## Features

| | |
|---|---|
| **Hold-to-record** | Hold `Right Ctrl` anywhere, release to transcribe |
| **Local transcription** | Whisper `large-v3` on your 4090, ~200ms |
| **Local AI cleanup** | vLLM removes filler words, fixes grammar, adds punctuation |
| **Spoken formatting** | Say "new line", "comma", "bullet list" — they become real formatting |
| **Traditional Chinese** | Input in Chinese is always output as 繁體中文 |
| **Works everywhere** | Any app: browser, VS Code, Slack, Word, Notepad… |
| **System tray** | 🔵 idle · 🔴 recording · 🟠 processing |
| **100+ languages** | Auto-detected by Whisper |
| **Zero cloud** | Nothing leaves your PC |

---

## Setup

The main app runs natively on Windows; vLLM runs inside WSL2 (it does not support native Windows builds) and exposes `localhost:8000` transparently:

| Env | Location | Used by |
|---|---|---|
| `.venv` | Windows, repo root | `flow.py` (dictation app) |
| `~/whype-vllm` | Inside WSL2 | `start_vllm.bat` (AI server) |

### Step 1 — Prerequisites

- **Python 3.12** — https://www.python.org/downloads/release/python-3120/
  *(PyTorch CUDA requires 3.10–3.12; Python 3.13 not yet supported)*
- **NVIDIA drivers with CUDA 12.x** — update via GeForce Experience
- **WSL2** with a Linux distro (Ubuntu recommended) — `wsl --install`
- **NVIDIA CUDA driver for WSL** — https://developer.nvidia.com/cuda/wsl
  *(required for GPU access inside WSL2)*
- **uv** — auto-installed by the install scripts

### Step 2 — Install the dictation app

```bat
install.bat
```

Creates `.venv`, installs PyTorch CUDA + Whisper + all UI deps.

### Step 3 — Install vLLM (inside WSL2)

```bat
install_vllm.bat
```

Installs `uv` inside WSL2, creates `~/whype-vllm`, and installs vLLM there. Takes a few minutes.

### Step 4 — Configure

Edit `%USERPROFILE%\.whype\config.json` (auto-created on first run):

```json
{
  "hotkey": "right ctrl",
  "whisper_model": "large-v3",
  "language": null,
  "ai_cleanup": true,
  "vllm_base_url": "http://localhost:8000",
  "vllm_model": "Qwen/Qwen3.5-4B",
  "vllm_max_tokens": 1024,
  "vllm_timeout": 30,
  "output_mode": "type"
}
```

### Step 5 — Start vLLM server

```bat
start_vllm.bat
```

Keep this window open. First run downloads model weights (~8 GB for Qwen3.5-4B).

### Step 6 — Start Whype

```bat
start_whype.bat
```

Look for the blue circle in your system tray.

---

## Usage

1. **Click** any text field you want to dictate into
2. **Hold `Right Ctrl`** — icon turns red
3. **Speak** naturally
4. **Release `Right Ctrl`** — icon turns orange while processing
5. **Done** — clean text appears

**Spoken formatting commands** understood by the AI cleanup:

| Say | Gets inserted |
|---|---|
| "comma" | `,` |
| "period" / "full stop" | `.` |
| "question mark" | `?` |
| "exclamation mark" | `!` |
| "colon" | `:` |
| "new line" / "new paragraph" | paragraph break |
| "first … second … third" | `- ` bullet list |

---

## Model selection (RTX 4090, 24 GB VRAM)

Whisper `large-v3` loads in **fp16** (~3 GB weights, ~6 GB total with CUDA overhead).
vLLM's `GPU_MEMORY_UTILIZATION=0.50` reserves 12 GB (model weights + KV cache).
Combined peak usage is roughly 18–20 GB out of 24 GB.

> **Why not lower than 0.50?** Qwen3.5-4B weights alone are ~8 GB. At 0.40 (9.6 GB),
> vLLM only has ~1.6 GB left for the KV cache — below its minimum, causing startup failure.

| Model | VRAM (weights) | Quality | Speed |
|---|---|---|---|
| `Qwen/Qwen3.5-4B` ✦ default | ~8 GB | ⭐⭐⭐⭐⭐ | Very fast |
| `Qwen/Qwen2.5-7B-Instruct` | ~14 GB | ⭐⭐⭐⭐⭐ | Fast |
| `mistralai/Mistral-7B-Instruct-v0.3` | ~14 GB | ⭐⭐⭐⭐⭐ | Fast |
| `microsoft/Phi-3-mini-4k-instruct` | ~8 GB | ⭐⭐⭐⭐ | Very fast |
| `google/gemma-2-2b-it` | ~5 GB | ⭐⭐⭐ | Fastest |

Change `MODEL=` in `start_vllm.bat` and `vllm_model` in `config.json` to switch models.
Larger models need a higher `GPU_MEMORY_UTILIZATION` to leave enough room for the KV cache.

---

## Configuration reference

| Key | Default | Description |
|---|---|---|
| `hotkey` | `"right ctrl"` | Any key name from the `keyboard` library |
| `whisper_model` | `"large-v3"` | Whisper model size |
| `language` | `null` | Force language e.g. `"zh"` for Chinese, or `null` for auto |
| `sample_rate` | `16000` | Audio capture sample rate (Hz) |
| `channels` | `1` | Audio channels |
| `min_duration` | `0.3` | Ignore recordings shorter than this (seconds) |
| `ai_cleanup` | `true` | Use vLLM to clean transcription |
| `vllm_base_url` | `"http://localhost:8000"` | vLLM server URL |
| `vllm_model` | `"Qwen/Qwen3.5-4B"` | Model ID served by vLLM |
| `vllm_max_tokens` | `1024` | Max output tokens from vLLM |
| `vllm_timeout` | `30` | Seconds before vLLM request times out |

---

## Run on Windows startup

1. Press `Win+R`, type `shell:startup`, press Enter
2. Create shortcuts to both `start_vllm.bat` and `start_whype.bat` in that folder

---

## Troubleshooting

**vLLM not reachable on startup**
→ Start `start_vllm.bat` first, wait for `Uvicorn running on...` before launching Whype. Whype will fall back to raw (uncleaned) transcription in the meantime.

**CUDA not detected**
→ Run `debug_whype.bat` to see output. Reinstall PyTorch:
`uv pip install torch --index-url https://download.pytorch.org/whl/cu124 --python .venv\Scripts\python.exe`

**CUDA not detected inside WSL2 (vLLM)**
→ Install the [NVIDIA CUDA driver for WSL](https://developer.nvidia.com/cuda/wsl). This is separate from the regular Windows NVIDIA driver.

**Hotkey not working**
→ Right-click `start_whype.bat` → "Run as administrator"

**Out of VRAM**
→ Use a smaller model. Avoid lowering `GPU_MEMORY_UTILIZATION` below what the model weights require — vLLM needs headroom for the KV cache on top of the weights (default is `0.50`).

**vLLM returns reasoning/thinking text**
→ This is Qwen3's chain-of-thought mode. It is already disabled via `enable_thinking: false` in the API call. If you see it, ensure your vLLM version supports `chat_template_kwargs`.

**Debug mode (visible console)**
→ Run `debug_whype.bat`
