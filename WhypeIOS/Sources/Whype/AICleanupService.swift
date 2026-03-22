import Foundation

/// Sends transcribed text to a remote vLLM-compatible endpoint for AI cleanup.
/// Mirrors the logic in flow.py, including the enable_thinking=false flag for Qwen3.
struct AICleanupService {
    let config: Config

    /// Returns the cleaned text, or the original `text` if cleanup is disabled or the server
    /// is unreachable (graceful degradation matches Whype's desktop behaviour).
    func cleanup(text: String) async -> String {
        guard config.aiCleanup, !text.isEmpty else { return text }
        do {
            return try await callVLLM(text: text)
        } catch {
            // Graceful fallback — return raw transcript
            return text
        }
    }

    // MARK: - Private

    private func callVLLM(text: String) async throws -> String {
        guard let url = URL(string: "\(config.vllmBaseURL)/v1/chat/completions") else {
            throw CleanupError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: config.vllmTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // chat_template_kwargs suppresses Qwen3 chain-of-thought output
        let body: [String: Any] = [
            "model": config.vllmModel,
            "max_tokens": config.vllmMaxTokens,
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": [
                ["role": "system", "content": config.cleanupSystemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CleanupError.badStatus
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CleanupError.unexpectedShape
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CleanupError: LocalizedError {
        case invalidURL
        case badStatus
        case unexpectedShape

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid vLLM URL in settings"
            case .badStatus: return "vLLM server returned a non-200 response"
            case .unexpectedShape: return "Could not parse vLLM response"
            }
        }
    }
}
