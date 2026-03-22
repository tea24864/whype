"""
Whype (Whisper to Type) - Wispr Flow clone for Windows with RTX 4090
Press and hold the hotkey (default: Right Ctrl) to record,
release to transcribe + AI-clean and type into the active window.

AI cleanup uses a locally running vLLM server (OpenAI-compatible API).
Start the server first with:  start_vllm.bat
"""

import sys
import os
import threading
import time
import json
import queue
from pathlib import Path
import urllib.request
import urllib.error

# ── Third-party imports ───────────────────────────────────────────────────────
import numpy as np
import sounddevice as sd
import keyboard
import pyperclip
import pyautogui
import pystray
from PIL import Image, ImageDraw
import whisper
import torch

# ── Config ────────────────────────────────────────────────────────────────────
CONFIG_FILE = Path.home() / ".whype" / "config.json"
DEFAULT_CONFIG = {
    # Recording
    "hotkey": "right ctrl",
    "sample_rate": 16000,
    "channels": 1,
    "min_duration": 0.3,

    # Whisper
    "whisper_model": "large-v3",
    "language": None,

    # AI cleanup via local vLLM (OpenAI-compatible)
    "ai_cleanup": True,
    "vllm_base_url": "http://localhost:8000",
    "vllm_model": "Qwen/Qwen3.5-4B",
    "vllm_max_tokens": 1024,
    "vllm_timeout": 30,

    # Output
    "output_mode": "type",
}

CLEANUP_SYSTEM_PROMPT = (
    "You are a dictation assistant. The user has spoken text that was transcribed "
    "by a speech-to-text model. Clean it up according to these rules:\n\n"
    "GRAMMAR & STYLE\n"
    "- Fix grammar and remove filler words (um, uh, like, you know).\n"
    "- Remove repeated or self-corrected words; keep the intended version.\n"
    "- Preserve the user's original meaning and voice.\n\n"
    "PUNCTUATION\n"
    "- Add correct sentence-ending punctuation (period, question mark, "
    "exclamation mark).\n"
    "- Add commas where natural spoken pauses indicate them.\n"
    "- If the user says 'comma', 'period', 'question mark', 'exclamation mark', "
    "or 'colon', replace the word with the corresponding punctuation symbol.\n\n"
    "FORMATTING\n"
    "- If the user says 'new line' or 'new paragraph', insert a paragraph break "
    "(blank line) at that point.\n"
    "- If the user dictates a list (e.g. 'first … second … third'), format it as "
    "a bullet list using '- ' for each item.\n"
    "- Capitalise the first word of every sentence.\n\n"
    "LANGUAGE\n"
    "- If the text is in Chinese, output in Traditional Chinese (繁體中文).\n"
    "- Convert any Simplified Chinese characters to their Traditional Chinese equivalents.\n\n"
    "Return ONLY the cleaned text — no preamble, no explanation, no quotes."
)

# ── State ─────────────────────────────────────────────────────────────────────
recording = False
audio_chunks = []
whisper_model = None
config = {}
tray_icon = None
status_queue = queue.Queue()


# ── Config helpers ────────────────────────────────────────────────────────────

def load_config() -> dict:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            saved = json.load(f)
        return {**DEFAULT_CONFIG, **saved}
    cfg = DEFAULT_CONFIG.copy()
    save_config(cfg)
    return cfg


def save_config(cfg: dict):
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


# ── Whisper ───────────────────────────────────────────────────────────────────

def load_whisper_model():
    global whisper_model
    model_name = config.get("whisper_model", "large-v3")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[Whype] Loading Whisper '{model_name}' on {device}…")
    whisper_model = whisper.load_model(model_name, device=device)
    print(f"[Whype] Whisper ready ✓")


def transcribe(audio_data: np.ndarray) -> str:
    sr = config["sample_rate"]
    duration = len(audio_data) / sr
    if duration < config.get("min_duration", 0.3):
        return ""
    audio_flat = audio_data.flatten().astype(np.float32)
    result = whisper_model.transcribe(
        audio_flat,
        language=config.get("language"),
        fp16=torch.cuda.is_available(),
        condition_on_previous_text=False,
    )
    return result["text"].strip()


# ── vLLM AI cleanup ───────────────────────────────────────────────────────────

def vllm_is_reachable() -> bool:
    """Quick health-check against the vLLM /health endpoint."""
    base = config.get("vllm_base_url", "http://localhost:8000").rstrip("/")
    try:
        req = urllib.request.Request(f"{base}/health", method="GET")
        with urllib.request.urlopen(req, timeout=2):
            return True
    except Exception:
        return False


def ai_cleanup(raw: str) -> str:
    """
    Send the raw transcript to a local vLLM server using the
    OpenAI-compatible /v1/chat/completions endpoint.
    Falls back to raw text if the server is unreachable or errors out.
    """
    if not raw:
        return raw

    base = config.get("vllm_base_url", "http://localhost:8000").rstrip("/")
    model = config.get("vllm_model", "Qwen/Qwen3.5-4B")
    max_tokens = config.get("vllm_max_tokens", 1024)
    timeout = config.get("vllm_timeout", 30)

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": CLEANUP_SYSTEM_PROMPT},
            {"role": "user", "content": raw},
        ],
        "max_tokens": max_tokens,
        "temperature": 0.3,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/v1/chat/completions",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer no-key",   # vLLM ignores this but needs the header
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"].strip()
    except urllib.error.URLError as e:
        print(f"[Whype] vLLM unreachable ({e}) – using raw transcript")
        return raw
    except Exception as e:
        print(f"[Whype] vLLM error: {e} – using raw transcript")
        return raw


# ── Audio ─────────────────────────────────────────────────────────────────────

def audio_callback(indata, frames, time_info, status):
    if recording:
        audio_chunks.append(indata.copy())


def start_recording():
    global recording, audio_chunks
    audio_chunks = []
    recording = True
    set_tray_status("recording")
    print("[Whype] 🔴 Recording…")


def stop_recording():
    global recording
    recording = False
    set_tray_status("processing")
    print("[Whype] ⏹  Stopped. Processing…")


def process_audio():
    """Transcribe + clean up, then type. Runs in a background thread."""
    if not audio_chunks:
        set_tray_status("idle")
        return

    audio_data = np.concatenate(audio_chunks, axis=0)

    raw_text = transcribe(audio_data)
    print(f"[Whype] Raw:   {raw_text!r}")
    if not raw_text:
        set_tray_status("idle")
        return

    if config.get("ai_cleanup"):
        final_text = ai_cleanup(raw_text)
        print(f"[Whype] Clean: {final_text!r}")
    else:
        final_text = raw_text

    type_or_paste(final_text)
    set_tray_status("idle")


# ── Output ────────────────────────────────────────────────────────────────────

def type_or_paste(text: str):
    if not text:
        return
    # Save clipboard, paste our text, restore — works with Unicode and is fast
    old_clip = ""
    try:
        old_clip = pyperclip.paste()
    except Exception:
        pass
    pyperclip.copy(text)
    pyautogui.hotkey("ctrl", "v")
    time.sleep(0.05)
    try:
        pyperclip.copy(old_clip)
    except Exception:
        pass


# ── Tray icon ─────────────────────────────────────────────────────────────────

ICON_COLORS = {
    "idle":       "#2196F3",   # Blue
    "recording":  "#F44336",   # Red
    "processing": "#FF9800",   # Orange
}

TRAY_LABELS = {
    "idle":       "Whype – Idle (hold hotkey to dictate)",
    "recording":  "Whype – Recording…",
    "processing": "Whype – Processing…",
}


def make_icon_image(color: str) -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([4, 4, 60, 60], fill=color)
    draw.rectangle([24, 14, 40, 38], fill="white")
    draw.ellipse([18, 32, 46, 44], fill="white")
    draw.rectangle([30, 44, 34, 52], fill="white")
    draw.rectangle([22, 50, 42, 54], fill="white")
    return img


def set_tray_status(status: str):
    status_queue.put(status)


def tray_update_loop():
    current = "idle"
    while True:
        try:
            status = status_queue.get(timeout=0.2)
        except queue.Empty:
            continue
        if status != current:
            current = status
            if tray_icon:
                tray_icon.icon = make_icon_image(ICON_COLORS.get(current, "#2196F3"))
                tray_icon.title = TRAY_LABELS.get(current, "Whype")


def open_config_editor():
    save_config(config)
    os.startfile(str(CONFIG_FILE))


def quit_app(icon, item):
    icon.stop()
    keyboard.unhook_all()
    sys.exit(0)


def build_tray():
    global tray_icon
    menu = pystray.Menu(
        pystray.MenuItem("Whype Dictation", None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Open Config", lambda icon, item: open_config_editor()),
        pystray.MenuItem("Quit", quit_app),
    )
    tray_icon = pystray.Icon(
        "whype_dictation",
        make_icon_image(ICON_COLORS["idle"]),
        TRAY_LABELS["idle"],
        menu,
    )
    return tray_icon


# ── Hotkey ────────────────────────────────────────────────────────────────────

def on_hotkey_press():
    if not recording:
        start_recording()


def on_hotkey_release():
    if recording:
        stop_recording()
        threading.Thread(target=process_audio, daemon=True).start()


def setup_hotkey():
    hk = config.get("hotkey", "right ctrl")
    keyboard.on_press_key(hk, lambda e: on_hotkey_press() if e.name == hk else None)
    keyboard.on_release_key(hk, lambda e: on_hotkey_release() if e.name == hk else None)
    print(f"[Whype] Hotkey: {hk!r}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    global config

    config = load_config()

    if torch.cuda.is_available():
        print(f"[Whype] GPU: {torch.cuda.get_device_name(0)}")
    else:
        print("[Whype] WARNING: CUDA not detected — transcription will be slow.")

    # Check vLLM availability
    if config.get("ai_cleanup"):
        if vllm_is_reachable():
            print(f"[Whype] vLLM server reachable at {config['vllm_base_url']} ✓")
        else:
            print(
                f"[Whype] WARNING: vLLM server not reachable at {config['vllm_base_url']}.\n"
                f"        AI cleanup will be skipped until the server is up.\n"
                f"        Start it with:  start_vllm.bat"
            )

    # Load Whisper in background
    threading.Thread(target=load_whisper_model, daemon=True).start()

    # Start audio stream
    stream = sd.InputStream(
        samplerate=config["sample_rate"],
        channels=config["channels"],
        dtype="float32",
        callback=audio_callback,
        blocksize=1024,
    )
    stream.start()
    print("[Whype] Audio stream started.")

    setup_hotkey()

    threading.Thread(target=tray_update_loop, daemon=True).start()

    icon = build_tray()
    print(f"[Whype] Running. Hold [{config['hotkey']}] to dictate.")
    icon.run()


if __name__ == "__main__":
    main()
