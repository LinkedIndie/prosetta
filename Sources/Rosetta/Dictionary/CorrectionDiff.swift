import Foundation

/// Finds word-level corrections between what Rosetta showed and what the user edited it to.
///
/// Adapted from Parla's `CorrectionCapture.swift` — the diffing logic there is pure text analysis
/// with no Accessibility dependency at all; only its neighbour `InsertionWatcher` (which reads text
/// back from *other* apps after Parla injects into them) used Accessibility, and that premise
/// doesn't exist here since Rosetta never injects into other apps. This applies the same word-level
/// alignment directly to Rosetta's own editable transcript field instead.
///
/// A **substitution** of one to three words inside otherwise-recognisable text counts as a
/// correction. A full rewrite is ignored on purpose — recording that as a correction would teach
/// the dictionary that one sentence means another, which is how a learning system poisons itself.
enum CorrectionDiff {

    struct Pair: Equatable, Hashable {
        let heard: String
        let meant: String
    }

    /// Below this, the person rewrote rather than corrected, and their new sentence is not evidence
    /// about the old one. Deliberately generous in the safe direction.
    static let minimumWordOverlap = 0.6

    /// A misheard name or bit of jargon is one to three words. Four or more consecutive changes is
    /// someone rephrasing a thought, which carries no information about what the engine misheard.
    static let maximumRunLength = 3

    static let minimumWordLength = 3

    // MARK: - The decision

    static func pairs(shown: String, edited: String) -> [Pair] {
        let before = words(shown)
        let after = words(edited)

        guard !before.isEmpty, !after.isEmpty else { return [] }
        guard before != after else { return [] }
        guard overlap(before, after) >= minimumWordOverlap else { return [] }

        return substitutions(from: before, to: after)
            .compactMap { run in
                let heard = run.heard.joined(separator: " ")
                let meant = run.meant.joined(separator: " ")
                guard isWorthLearning(heard: heard, meant: meant) else { return nil }
                return Pair(heard: heard, meant: meant)
            }
    }

    private static func isWorthLearning(heard: String, meant: String) -> Bool {
        guard !heard.isEmpty, !meant.isEmpty, heard != meant else { return false }
        guard heard.count >= minimumWordLength, meant.count >= minimumWordLength else { return false }

        let strippedHeard = heard.filter { !$0.isWhitespace }
        let strippedMeant = meant.filter { !$0.isWhitespace }
        guard strippedHeard != strippedMeant else { return false }

        let a = Set(heard.lowercased().filter { $0.isLetter })
        let b = Set(meant.lowercased().filter { $0.isLetter })
        guard !a.isEmpty, !b.isEmpty else { return false }
        return !a.intersection(b).isEmpty
    }

    // MARK: - Word-level alignment

    private struct Run {
        let heard: [String]
        let meant: [String]
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { token in
                String(token).trimmingCharacters(
                    in: CharacterSet.punctuationCharacters
                        .union(.symbols)
                        .subtracting(CharacterSet(charactersIn: "'’-"))
                )
            }
            .filter { !$0.isEmpty }
    }

    private static func overlap(_ before: [String], _ after: [String]) -> Double {
        var remaining = counts(after)
        var kept = 0
        for word in before {
            let key = word.lowercased()
            if let n = remaining[key], n > 0 {
                remaining[key] = n - 1
                kept += 1
            }
        }
        return Double(kept) / Double(before.count)
    }

    private static func counts(_ words: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for word in words { out[word.lowercased(), default: 0] += 1 }
        return out
    }

    private static func substitutions(from before: [String], to after: [String]) -> [Run] {
        let anchors = longestCommonSubsequence(before, after)

        var runs: [Run] = []
        var i = 0, j = 0
        var heard: [String] = []
        var meant: [String] = []

        func flush() {
            defer { heard = []; meant = [] }
            guard !heard.isEmpty, !meant.isEmpty else { return }
            guard heard.count <= maximumRunLength, meant.count <= maximumRunLength else { return }
            runs.append(Run(heard: heard, meant: meant))
        }

        func absorb(_ gapHeard: [String], _ gapMeant: [String]) {
            guard !gapHeard.isEmpty || !gapMeant.isEmpty else { return }
            if gapHeard.isEmpty != gapMeant.isEmpty {
                flush()
                return
            }
            heard.append(contentsOf: gapHeard)
            meant.append(contentsOf: gapMeant)
        }

        for (ai, aj) in anchors {
            absorb(Array(before[i..<ai]), Array(after[j..<aj]))

            if before[ai] != after[aj] {
                heard.append(before[ai])
                meant.append(after[aj])
            } else {
                flush()
            }

            i = ai + 1
            j = aj + 1
        }

        absorb(Array(before[i...]), Array(after[j...]))
        flush()

        return runs
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }

        var table = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                table[i][j] = a[i].lowercased() == b[j].lowercased()
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var out: [(Int, Int)] = []
        var i = 0, j = 0
        while i < m, j < n {
            if a[i].lowercased() == b[j].lowercased() {
                out.append((i, j))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return out
    }
}
