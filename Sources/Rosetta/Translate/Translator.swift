import Foundation

/// One thing that can turn spoken-language text into another language's text.
///
/// Two conformances: `CLITranslator` (shells out to the `claude` CLI, rides the user's existing
/// Claude Code login, no separate credential) and `APITranslator` (calls the Messages API directly
/// with a user-supplied API key). Rosetta prefers the CLI when it's present — genuinely zero setup
/// for anyone who already has Claude Code — and falls back to the API key otherwise, which is what
/// makes Rosetta usable by someone who has never installed Claude Code at all.
protocol Translator: Sendable {
    var isAvailable: Bool { get }
    func translate(_ text: String, sourceLanguage: String, targetLanguage: String) async throws -> String
    func retranslate(_ text: String, previousTranslation: String, sourceLanguage: String, targetLanguage: String) async throws -> String
}

extension Translator {
    func retranslate(_ text: String, previousTranslation: String, sourceLanguage: String, targetLanguage: String) async throws -> String {
        try await translate(text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }
}

enum TranslatorError: LocalizedError {
    case unavailable
    case emptyResult
    case malformedResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "No translator is configured — install Claude Code, or add your Anthropic API key in Settings."
        case .emptyResult:
            "Claude returned nothing to work with."
        case .malformedResponse:
            "The response wasn't in the expected shape."
        case .requestFailed(let detail):
            "Translation request failed: \(detail)"
        }
    }
}
