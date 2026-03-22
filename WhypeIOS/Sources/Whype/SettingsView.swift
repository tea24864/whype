import SwiftUI

struct SettingsView: View {
    @Binding var config: Config
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                whisperSection
                aiCleanupSection
                systemPromptSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.save()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var whisperSection: some View {
        Section {
            Picker("Model", selection: $config.whisperModel) {
                Text("tiny (~39 MB)").tag("tiny")
                Text("base (~74 MB)").tag("base")
                Text("small (~244 MB)").tag("small")
                Text("medium (~769 MB)").tag("medium")
                Text("large-v3 (~1.5 GB)").tag("large-v3")
            }
            languageField
        } header: {
            Text("Whisper (On-Device)")
        } footer: {
            Text("Model files are downloaded from Hugging Face on first use. large-v3 gives the best accuracy; tiny is fastest.")
        }
    }

    private var languageField: some View {
        HStack {
            Text("Language")
            Spacer()
            TextField("auto-detect", text: Binding(
                get: { config.language ?? "" },
                set: { config.language = $0.isEmpty ? nil : $0 }
            ))
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(.secondary)
        }
    }

    private var aiCleanupSection: some View {
        Section {
            Toggle("Enable AI Cleanup", isOn: $config.aiCleanup)

            if config.aiCleanup {
                LabeledContent("vLLM URL") {
                    TextField("http://host:8000", text: $config.vllmBaseURL)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Model") {
                    TextField("Qwen/Qwen3-4B", text: $config.vllmModel)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    "Max tokens: \(config.vllmMaxTokens)",
                    value: $config.vllmMaxTokens,
                    in: 64 ... 4096,
                    step: 64
                )
                Stepper(
                    "Timeout: \(Int(config.vllmTimeout)) s",
                    value: $config.vllmTimeout,
                    in: 5 ... 120,
                    step: 5
                )
            }
        } header: {
            Text("AI Cleanup (Remote vLLM)")
        } footer: {
            Text("Point this at your vLLM server. The app falls back to the raw transcript if the server is unreachable.")
        }
    }

    private var systemPromptSection: some View {
        Section {
            TextEditor(text: $config.cleanupSystemPrompt)
                .frame(minHeight: 140)
                .font(.footnote)
            Button("Reset to Default", role: .destructive) {
                config.cleanupSystemPrompt = Config.defaultCleanupPrompt
            }
        } header: {
            Text("System Prompt")
        }
    }
}
