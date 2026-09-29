import AVFoundation
import Foundation
import Observation

/// Ties audio capture, transcription, the dictionary, and translation together, and drives the
/// single on-screen state machine: idle → recording → transcribing → translating → done.
@MainActor
@Observable
final class AppModel {

    enum RecordState: Equatable {
        case idle
        case recording
        case transcribing
        case translating(elapsedSeconds: Int)
        case done
        case failed(String)
    }

    var recordState: RecordState = .idle
    var transcript: String = ""
    var translation: String = ""
    var sourceLanguageID: String = Settings.sourceLocaleIdentifier
    var targetLanguage: String = Settings.targetLanguage
    let availableSourceLanguages: [Settings.LanguageOption] = Settings.sourceLanguages
    var dictionaryEntries: [DictionaryEntry] = []
    var pendingCorrections: [CorrectionDiff.Pair] = []
    var permissionDenied = false
    var apiKeyConfigured = KeychainStore.load()?.isEmpty == false
    var cliLoggedIn = CLITranslator.isLoggedIn

    private let audio = AudioCapture()
    private let transcription = TranscriptionManager()
    private let dictionary = DictionaryStore()
    private let cliTranslator = CLITranslator()
    private let apiTranslator = APITranslator()

    private var lastShownTranscript = ""
    private var lastTranslationSource = ""
    private var lastTranslationTarget = ""
    private var activeInput: SpeechEngine.Input?
    private var translationTicker: Task<Void, Never>?

    /// The CLI is preferred when present and signed in — genuinely zero setup for anyone who
    /// already has Claude Code — falling back to a user-supplied API key otherwise.
    private var activeTranslator: Translator? {
        if cliTranslator.isAvailable && cliLoggedIn { return cliTranslator }
        if apiTranslator.isAvailable { return apiTranslator }
        return nil
    }

    var hasTranslator: Bool { activeTranslator != nil }

    var translatorStatus: String {
        if cliTranslator.isAvailable {
            return cliLoggedIn ? "Using Claude Code" : "Claude Code installed — sign in to use"
        }
        if apiTranslator.isAvailable { return "Using your API key" }
        return "No translator configured"
    }

    // MARK: - Startup

    func start() async {
        let micGranted = await Permissions.requestMicrophone()
        let speechGranted = await Permissions.requestSpeechRecognition()
        guard micGranted && speechGranted else {
            permissionDenied = true
            return
        }

        FileLog.startSession()
        await dictionary.load()
        dictionaryEntries = await dictionary.all()

        do {
            try audio.prepare()
        } catch {
            recordState = .failed(error.localizedDescription)
            return
        }

        cliLoggedIn = CLITranslator.isLoggedIn
        Log.app.info("ready — CLI: \(cliLoggedIn ? "signed in" : "not signed in")")
    }

    func recheckCLILogin() {
        cliLoggedIn = CLITranslator.isLoggedIn
    }

    // MARK: - Language selection

    func setSourceLanguage(_ localeID: String) {
        sourceLanguageID = localeID
        Settings.sourceLocaleIdentifier = localeID
    }

    func setTargetLanguage(_ language: String) {
        targetLanguage = language
        Settings.targetLanguage = language
    }

    // MARK: - API key

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed)
        apiKeyConfigured = true
    }

    func removeAPIKey() {
        KeychainStore.delete()
        apiKeyConfigured = false
    }

    // MARK: - Recording

    func toggleRecording() {
        switch recordState {
        case .idle, .done, .failed:
            beginRecording()
        case .recording:
            stopRecording()
        case .transcribing, .translating:
            break
        }
    }

    private func beginRecording() {
        transcript = ""
        translation = ""
        pendingCorrections = []
        recordState = .recording

        let localeID = sourceLanguageID
        Task {
            do {
                let input = try await transcription.beginUtterance(localeID: localeID)
                activeInput = input

                let format = await transcription.preferredFormat(for: localeID)
                let converter = FormatConverter(target: format)

                try audio.beginUtterance { buffer in
                    guard let converted = converter.convert(buffer) else { return }
                    input.send(converted)
                }
            } catch {
                recordState = .failed(error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        recordState = .transcribing
        audio.endUtterance()
        activeInput?.finish()
        activeInput = nil

        let source = sourceLanguageID
        let target = targetLanguage

        Task {
            let raw = await transcription.finish()
            let (corrected, _) = await dictionary.correct(raw)
            let cleaned = Self.removeFiller(corrected)

            transcript = cleaned
            lastShownTranscript = cleaned

            guard let translator = activeTranslator else {
                recordState = .failed(TranslatorError.unavailable.localizedDescription)
                return
            }

            await translate(cleaned, sourceLanguage: source, targetLanguage: target, using: translator)
        }
    }

    func retranslate() {
        guard !transcript.isEmpty, let translator = activeTranslator else { return }
        let source = sourceLanguageID
        let target = targetLanguage
        let languageChanged = source != lastTranslationSource || target != lastTranslationTarget
        let previous = languageChanged ? nil : translation

        Task {
            await translate(transcript, sourceLanguage: source, targetLanguage: target, previousTranslation: previous, using: translator)
        }
    }

    private func translate(_ text: String, sourceLanguage: String, targetLanguage: String, previousTranslation: String? = nil, using translator: Translator) async {
        recordState = .translating(elapsedSeconds: 0)

        translationTicker?.cancel()
        translationTicker = Task { [weak self] in
            var elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
                guard let self, case .translating = self.recordState else { return }
                self.recordState = .translating(elapsedSeconds: elapsed)
            }
        }

        do {
            let result: String
            if let prev = previousTranslation, !prev.isEmpty {
                result = try await translator.retranslate(text, previousTranslation: prev, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            } else {
                result = try await translator.translate(text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            }
            translationTicker?.cancel()
            translation = result
            lastTranslationSource = sourceLanguage
            lastTranslationTarget = targetLanguage
            recordState = .done
        } catch {
            translationTicker?.cancel()
            recordState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Editing the transcript, and learning from it

    func editTranscript(to newText: String) {
        let pairs = CorrectionDiff.pairs(shown: lastShownTranscript, edited: newText)
        transcript = newText
        lastShownTranscript = newText
        pendingCorrections.append(contentsOf: pairs.filter { pair in !pendingCorrections.contains(pair) })
    }

    func acceptCorrection(_ pair: CorrectionDiff.Pair) {
        pendingCorrections.removeAll { $0 == pair }
        Task {
            await dictionary.add(.correction(hear: pair.heard, write: pair.meant))
            dictionaryEntries = await dictionary.all()
        }
    }

    func dismissCorrection(_ pair: CorrectionDiff.Pair) {
        pendingCorrections.removeAll { $0 == pair }
    }

    // MARK: - Dictionary management

    func addDictionaryEntry(_ entry: DictionaryEntry) {
        Task {
            await dictionary.add(entry)
            dictionaryEntries = await dictionary.all()
        }
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        Task {
            await dictionary.remove(id: entry.id)
            dictionaryEntries = await dictionary.all()
        }
    }

    func toggleDictionaryEntry(_ entry: DictionaryEntry) {
        var updated = entry
        updated.isEnabled.toggle()
        Task {
            await dictionary.update(updated)
            dictionaryEntries = await dictionary.all()
        }
    }

    // MARK: - Level meter

    var currentLevel: Float { audio.level }

    // MARK: - Filler word removal

    private static let fillerWords: Set<String> = [
        "um", "umm", "ummm",
        "uh", "uhh", "uhhh", "uhm", "uhhm",
        "er", "err",
        "hmm", "hmmm", "hm",
        "ah", "ahh", "ahhh",
        "mhm", "mmhm", "mm", "mmm",
        "äh", "ähm",
        "euh",
    ]

    static func removeFiller(_ text: String) -> String {
        var kept = [String]()
        for token in text.components(separatedBy: .whitespaces) where !token.isEmpty {
            let core = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if !fillerWords.contains(core) {
                kept.append(token)
            }
        }
        return kept.joined(separator: " ")
    }
}
