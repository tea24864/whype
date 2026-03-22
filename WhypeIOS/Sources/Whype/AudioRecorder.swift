import AVFoundation
import Foundation

/// Captures microphone audio and resamples it to 16 kHz mono Float32,
/// the format WhisperKit (and Whisper in general) expects.
@MainActor
class AudioRecorder: ObservableObject {
    @Published var isRecording = false

    private var audioEngine = AVAudioEngine()
    private var audioSamples: [Float] = []

    // Whisper requires 16 kHz mono
    private static let targetSampleRate: Double = 16_000

    // MARK: - Public API

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        audioSamples = []
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.unsupportedFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = Self.targetSampleRate / inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputCapacity > 0,
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)
            else { return }

            var conversionError: NSError?
            converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard conversionError == nil,
                  let channelData = outputBuffer.floatChannelData
            else { return }

            let samples = Array(UnsafeBufferPointer(
                start: channelData[0],
                count: Int(outputBuffer.frameLength)
            ))

            Task { @MainActor [weak self] in
                self?.audioSamples.append(contentsOf: samples)
            }
        }

        try audioEngine.start()
        isRecording = true
    }

    /// Stops recording and returns the accumulated Float32 samples at 16 kHz.
    func stopRecording() -> [Float] {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        return audioSamples
    }

    // MARK: - Helpers

    /// Duration of recorded audio in seconds.
    var recordedDuration: Double {
        Double(audioSamples.count) / Self.targetSampleRate
    }

    enum AudioError: LocalizedError {
        case unsupportedFormat
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Could not create 16 kHz audio format"
            case .converterCreationFailed: return "Could not create audio format converter"
            }
        }
    }
}
