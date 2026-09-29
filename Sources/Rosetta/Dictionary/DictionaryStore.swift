import Foundation

/// Loads, saves and serves the dictionary. Adapted from Parla's `DictionaryStore.swift` — same
/// design (readable JSON, deliberately hand-editable, one choke-point in `add()` that runs every
/// new rule through `CorrectionGuard`), with an empty starter set rather than Parla's own seed:
/// those corrections were tuned to one specific person's voice and colleagues, and wouldn't mean
/// anything here.
actor DictionaryStore {

    private let file: URL
    private var entries: [DictionaryEntry] = []
    private var corrector: DictionaryCorrector

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "Rosetta", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "dictionary.json")
        corrector = DictionaryCorrector(entries: [])
    }

    func load() {
        guard let data = try? Data(contentsOf: file) else {
            entries = []
            corrector = DictionaryCorrector(entries: entries)
            Log.app.info("dictionary: no file yet, starting empty")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([DictionaryEntry].self, from: data) else {
            Log.app.error("dictionary file present but unreadable — leaving it alone rather than overwriting")
            return
        }

        entries = decoded
        deduplicate()
        corrector = DictionaryCorrector(entries: entries)
        Log.app.info("dictionary loaded — \(entries.count) entries, \(corrector.count) active rules")
    }

    /// Removes duplicates already sitting in a user's file, keeping the first of each (and any
    /// `timesFired` count it accumulated).
    private func deduplicate() {
        var seen = Set<String>()
        var unique: [DictionaryEntry] = []
        for entry in entries {
            let key = Self.key(for: entry)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(entry)
        }
        guard unique.count != entries.count else { return }
        let removed = entries.count - unique.count
        entries = unique
        save()
        Log.app.info("dictionary: removed \(removed) duplicate entries")
    }

    private static func key(for entry: DictionaryEntry) -> String {
        "\(entry.kind.rawValue)|\(entry.hear.lowercased())"
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Use

    /// Applies the correction pass. Deliberately run on EACH candidate transcript before Claude
    /// arbitrates between them — see `ClaudeTranslator` — rather than only on the winner, since
    /// there's no local way to know which candidate is the real one before Claude judges it.
    func correct(_ text: String) -> (text: String, applied: [AppliedCorrection]) {
        let result = corrector.apply(to: text)

        if !result.applied.isEmpty {
            let fired = Set(corrector.firedEntryIDs(in: text))
            for index in entries.indices where fired.contains(entries[index].id) {
                entries[index].timesFired += 1
            }
            save()
        }

        return result
    }

    // MARK: - Editing

    func all() -> [DictionaryEntry] { entries }

    func add(_ entry: DictionaryEntry) {
        if entry.kind == .correction {
            let verdict = CorrectionGuard.judge(hear: entry.hear, write: entry.write)
            guard verdict == .allowed else {
                Log.app.warning("dictionary: refused rule \(entry.hear) → \(entry.write) — \(CorrectionGuard.explain(verdict) ?? "unsafe")")
                return
            }
        }

        entries.append(entry)
        corrector = DictionaryCorrector(entries: entries)
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        corrector = DictionaryCorrector(entries: entries)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        corrector = DictionaryCorrector(entries: entries)
        save()
    }

    var fileURL: URL { file }
}
