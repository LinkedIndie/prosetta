import Foundation

/// Refuses to create a correction rule that would rewrite ordinary text. Copied verbatim from
/// Parla's `CorrectionGuard.swift` — see that file's own history for the incident (a rule set that
/// silently rewrote "a creative director" into a company codename 950 times) that established the
/// test below: a term someone dictates doesn't begin with an article or preposition; a sentence
/// fragment accidentally promoted to a rule almost always does.
enum CorrectionGuard {

    static let openers: Set<String> = [
        "the", "a", "an", "and", "or", "but", "for", "with", "of", "to", "in", "on", "at",
        "by", "from", "as", "that", "this", "it", "is", "was", "are", "were",
        "only", "just", "very", "so", "then", "than", "if", "when", "while",
    ]

    enum Verdict: Equatable {
        case allowed
        case fragment(opener: String)
        case empty
        case selfMapping
    }

    static func judge(hear: String, write: String) -> Verdict {
        let trimmed = hear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if trimmed == write.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .selfMapping
        }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1, let first = words.first else { return .allowed }

        let opener = first.trimmingCharacters(in: .punctuationCharacters).lowercased()
        return openers.contains(opener) ? .fragment(opener: opener) : .allowed
    }

    static func allows(hear: String, write: String) -> Bool {
        judge(hear: hear, write: write) == .allowed
    }

    static func explain(_ verdict: Verdict) -> String? {
        switch verdict {
        case .allowed:
            return nil
        case .empty:
            return "There is nothing to correct."
        case .selfMapping:
            return "That already matches what Rosetta types, so a rule would change nothing."
        case .fragment(let opener):
            return "\u{201C}\(opener)\u{201D} starts an ordinary sentence, so a rule beginning with it "
                 + "would rewrite normal writing rather than one term. Try just the words that name "
                 + "the thing."
        }
    }
}
