import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var transcriber = TranscriptionService()

    @State private var config = Config.load()
    @State private var pipeline: AppPipeline = .idle
    @State private var transcript = ""
    @State private var showSettings = false
    @State private var copied = false

    // Minimum recording length to bother transcribing (matches Whype's 0.3 s)
    private static let minDuration = 0.3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelLoadingBanner
                transcriptArea
                Spacer(minLength: 0)
                statusLabel
                recordButton
                    .padding(.bottom, 48)
            }
            .navigationTitle("Whype")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: onSettingsDismiss) {
                SettingsView(config: $config)
            }
        }
        .task {
            await transcriber.loadModel(config.whisperModel)
        }
    }

    // MARK: - Subviews

    /// Shown while WhisperKit downloads / initialises the model.
    @ViewBuilder
    private var modelLoadingBanner: some View {
        switch transcriber.state {
        case .unloaded:
            bannerView(text: "Whisper model not loaded", color: .orange)
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading Whisper model…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        case .failed(let msg):
            bannerView(text: "Model error: \(msg)", color: .red)
        case .ready:
            EmptyView()
        }
    }

    private func bannerView(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.1))
    }

    private var transcriptArea: some View {
        Group {
            if transcript.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(pipeline == .idle ? "Tap the button to start dictating" : "")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(transcript)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 320)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .overlay(alignment: .topTrailing) {
                    copyButton
                        .padding(8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = transcript
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.default, value: copied)
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pipeline.statusColor)
                .frame(width: 8, height: 8)
            Text(pipeline.statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    private var recordButton: some View {
        Button {
            Task { await handleTap() }
        } label: {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 88, height: 88)
                    .shadow(radius: recorder.isRecording ? 8 : 4)

                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .disabled(!transcriber.state.isReady || pipeline == .transcribing || pipeline == .cleaningUp)
        .scaleEffect(recorder.isRecording ? 1.08 : 1.0)
        .animation(.spring(duration: 0.25), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Logic

    private func handleTap() async {
        if recorder.isRecording {
            await stopAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
            pipeline = .recording
        } catch {
            pipeline = .idle
        }
    }

    private func stopAndProcess() async {
        let samples = recorder.stopRecording()

        guard recorder.recordedDuration >= Self.minDuration else {
            pipeline = .idle
            return
        }

        // Transcribe
        pipeline = .transcribing
        let raw: String
        do {
            raw = try await transcriber.transcribe(
                samples: samples,
                language: config.language?.isEmpty == false ? config.language : nil
            )
        } catch {
            pipeline = .idle
            return
        }

        // AI cleanup (falls back to raw on failure)
        if config.aiCleanup {
            pipeline = .cleaningUp
            transcript = await AICleanupService(config: config).cleanup(text: raw)
        } else {
            transcript = raw
        }

        // Auto-copy to clipboard
        UIPasteboard.general.string = transcript
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }

        pipeline = .idle
    }

    private func onSettingsDismiss() {
        // Reload model if the model name changed
        Task {
            await transcriber.loadModel(config.whisperModel)
        }
    }
}

// MARK: - Pipeline state

enum AppPipeline: Equatable {
    case idle, recording, transcribing, cleaningUp

    var statusLabel: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .cleaningUp: return "Cleaning up…"
        }
    }

    var statusColor: Color {
        switch self {
        case .idle: return .green
        case .recording: return .red
        case .transcribing: return .orange
        case .cleaningUp: return .blue
        }
    }
}
