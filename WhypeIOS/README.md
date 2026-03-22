# Whype iOS

An iOS companion to [Whype](../README.md) — privacy-first voice dictation using on-device Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit), with optional AI cleanup via your remote vLLM server.

## Features

- On-device transcription using OpenAI Whisper (same model as the desktop app)
- Tap to start / tap to stop recording
- Optional AI text cleanup via your remote vLLM endpoint (same API as the desktop app)
- Configurable model size, language, vLLM URL, model ID, system prompt
- Auto-copies result to clipboard
- Graceful fallback to raw transcript when vLLM is unreachable

## Requirements

- Xcode 15+
- iOS 16+ device or simulator (WhisperKit requires Neural Engine for good performance; a real device is recommended for large-v3)
- macOS for building

## Setup in Xcode

1. **Clone the repo** on your Mac.
2. **Open Xcode** → File → Open → select `WhypeIOS/Package.swift`.
   - Xcode will resolve the WhisperKit dependency automatically.
3. **Configure signing**: Select the `Whype` scheme → Signing & Capabilities → set your Team.
4. The `Info.plist` in `Sources/Whype/` already contains the `NSMicrophoneUsageDescription`. In Xcode's target settings, set **Info.plist File** to `Sources/Whype/Info.plist` if it isn't picked up automatically.
5. **Run** on a device or simulator.

> **First run:** WhisperKit downloads the selected model from Hugging Face. `large-v3` is ~1.5 GB; `small` (~244 MB) is a good balance of speed and accuracy on older hardware. The app shows a loading indicator until the model is ready.

## Architecture

| File | Role |
|------|------|
| `WhypeApp.swift` | `@main` entry point |
| `ContentView.swift` | Main UI — record button, transcript display, status |
| `SettingsView.swift` | Settings sheet (model, language, vLLM config, system prompt) |
| `AudioRecorder.swift` | `AVAudioEngine` capture → 16 kHz mono Float32 |
| `TranscriptionService.swift` | WhisperKit wrapper with async model loading |
| `AICleanupService.swift` | HTTP POST to `/v1/chat/completions` on your remote vLLM |
| `Config.swift` | `Codable` settings persisted in `UserDefaults` |

## Data Flow

```
Tap (start) → AVAudioEngine records 16 kHz PCM
Tap (stop)  → samples passed to WhisperKit.transcribe()
            → (if AI cleanup enabled) POST to remote vLLM /v1/chat/completions
            → cleaned text shown + auto-copied to clipboard
```

## vLLM Setup

Point the app at your existing vLLM server (the same one Whype uses on Windows/WSL2). In Settings:

- **vLLM URL**: `http://<your-server-ip>:8000`
- **Model**: e.g. `Qwen/Qwen3-4B`

The app sends `chat_template_kwargs: {"enable_thinking": false}` to suppress Qwen3's chain-of-thought output, matching the desktop behaviour.
