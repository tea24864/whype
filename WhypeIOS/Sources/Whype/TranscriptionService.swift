import Foundation
import WhisperKit

/// Wraps WhisperKit to provide on-device transcription.
/// The model is downloaded from Hugging Face on first use (~1.5 GB for large-v3).
@MainActor
class TranscriptionService: ObservableObject {
    @Published var state: ModelState = .unloaded

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?

    enum ModelState: Equatable {
        case unloaded
        case loading(progress: Double)  // 0.0 – 1.0
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    // MARK: - Model loading

    /// Load (or re-load) the named Whisper model. No-ops if already loaded.
    func loadModel(_ modelName: String) async {
        guard loadedModelName != modelName else { return }
        state = .loading(progress: 0)
        do {
            whisperKit = try await WhisperKit(
                model: modelName,
                verbose: false
            )
            loadedModelName = modelName
            state = .ready
        } catch {
            whisperKit = nil
            loadedModelName = nil
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Transcription

    /// Transcribe a flat array of 16 kHz mono Float32 samples.
    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let whisperKit, state.isReady else {
            throw TranscriptionError.modelNotReady
        }

        var options = DecodingOptions()
        if let language, !language.isEmpty {
            options.language = language
        }
        // Speed up inference on device: skip token-level timestamps unless needed
        options.withoutTimestamps = true

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        return results
            .compactMap { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    enum TranscriptionError: LocalizedError {
        case modelNotReady

        var errorDescription: String? {
            "Whisper model is not ready. Please wait for it to finish loading."
        }
    }
}
