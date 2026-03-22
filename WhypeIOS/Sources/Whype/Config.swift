import Foundation

struct Config: Codable {
    var vllmBaseURL: String = "http://localhost:8000"
    var vllmModel: String = "Qwen/Qwen3-4B"
    var vllmMaxTokens: Int = 1024
    var vllmTimeout: Double = 30
    var whisperModel: String = "large-v3"
    var language: String? = nil
    var aiCleanup: Bool = true
    var cleanupSystemPrompt: String = Config.defaultCleanupPrompt

    static let defaultCleanupPrompt = """
        You are a transcription cleanup assistant. Your job is to take raw speech-to-text output and return polished, publication-ready text. Rules:
        - Fix grammar and punctuation.
        - Handle spoken formatting commands: "new line" → newline, "new paragraph" → paragraph break, "comma" → ,  "period" / "full stop" → .  "question mark" → ?  "exclamation mark" → !
        - Remove filler words (um, uh, like) only when clearly unintentional.
        - Do NOT add commentary, explanations, or quotation marks around the output.
        - Return only the cleaned text, nothing else.
        - If the input is Chinese, output Traditional Chinese (繁體中文).
        """

    private static let defaultsKey = "whype_config"

    static func load() -> Config {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else {
            return Config()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Config.defaultsKey)
        }
    }
}
