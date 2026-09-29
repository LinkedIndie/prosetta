import Foundation

/// A correction that actually fired. Copied verbatim from Parla's `ParlaDictionary`.
struct AppliedCorrection: Codable, Hashable, Sendable {
    let from: String
    let to: String
    let count: Int
}

/// Rewrites transcribed text using the dictionary's correction pairs. Copied verbatim from Parla's
/// `DictionaryCorrector.swift` — longest match first, whole-word only, glued/hyphenated words still
/// match, Unicode normalised before matching (this dictionary will hold plenty of accented names).
struct DictionaryCorrector: Sendable {

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String
        let trigger: String
        let entryID: UUID
    }

    private let rules: [Rule]

    init(entries: [DictionaryEntry]) {
        let corrections = entries
            .filter { $0.isEnabled && $0.kind == .correction }
            .filter { !$0.hear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.hear.count > $1.hear.count }

        rules = corrections.compactMap { entry in
            guard let regex = Self.makeRegex(for: entry.hear) else { return nil }
            return Rule(
                regex: regex,
                replacement: NSRegularExpression.escapedTemplate(for: entry.write),
                trigger: entry.hear,
                entryID: entry.id
            )
        }
    }

    var isEmpty: Bool { rules.isEmpty }
    var count: Int { rules.count }

    func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        var working = text.precomposedStringWithCanonicalMapping
        var applied: [AppliedCorrection] = []

        for rule in rules {
            let range = NSRange(working.startIndex..., in: working)
            let matches = rule.regex.numberOfMatches(in: working, range: range)
            guard matches > 0 else { continue }

            working = rule.regex.stringByReplacingMatches(
                in: working,
                range: range,
                withTemplate: rule.replacement
            )
            applied.append(AppliedCorrection(from: rule.trigger, to: rule.replacement, count: matches))
        }

        return (working, applied)
    }

    func firedEntryIDs(in text: String) -> [UUID] {
        guard !rules.isEmpty, !text.isEmpty else { return [] }
        let working = text.precomposedStringWithCanonicalMapping
        let range = NSRange(working.startIndex..., in: working)
        return rules.compactMap { rule in
            rule.regex.numberOfMatches(in: working, range: range) > 0 ? rule.entryID : nil
        }
    }

    // MARK: - Pattern building

    static func makeRegex(for trigger: String) -> NSRegularExpression? {
        let normalised = trigger
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        let parts = normalised
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\u{2011}" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }

        guard !parts.isEmpty else { return nil }

        let body = parts.joined(separator: "[\\s\\-]*")
        let pattern = "\\b\(body)\\b"

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
