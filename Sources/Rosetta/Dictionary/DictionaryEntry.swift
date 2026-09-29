import Foundation

/// One thing the dictionary knows. Copied verbatim from Parla's `ParlaDictionary/DictionaryEntry.swift`.
///
/// - **vocabulary** — a word or phrase worth knowing exists.
/// - **correction** — when you hear X, write Y. Applied after transcription, deterministically.
struct DictionaryEntry: Codable, Hashable, Sendable, Identifiable {

    enum Kind: String, Codable, Sendable {
        case vocabulary
        case correction
    }

    var id: UUID
    var kind: Kind

    /// What the engine produces. For a vocabulary entry this is the word itself.
    var hear: String
    /// What should be written instead. Empty for a vocabulary entry.
    var write: String

    var isEnabled: Bool
    var createdAt: Date
    var timesFired: Int

    init(
        id: UUID = UUID(),
        kind: Kind,
        hear: String,
        write: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        timesFired: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.hear = hear
        self.write = write
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.timesFired = timesFired
    }

    static func vocabulary(_ word: String) -> DictionaryEntry {
        DictionaryEntry(kind: .vocabulary, hear: word)
    }

    static func correction(hear: String, write: String) -> DictionaryEntry {
        DictionaryEntry(kind: .correction, hear: hear, write: write)
    }

    // MARK: - Risk

    /// How dangerous this entry is to apply blindly. A rule for a single common word will fire
    /// constantly and wrongly — surfaced rather than blocked, since the user knows their own
    /// vocabulary better than any heuristic does.
    enum Risk: Sendable {
        case safe
        case ambiguous(String)
    }

    var risk: Risk {
        guard kind == .correction else { return .safe }

        let trigger = hear.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trigger.split(whereSeparator: { $0 == " " || $0 == "-" })

        guard words.count == 1 else { return .safe }

        if trigger.count <= 5 {
            return .ambiguous(
                "\"\(trigger)\" is a single short word. It may match ordinary text and rewrite things you didn't mean to change."
            )
        }
        return .safe
    }
}
