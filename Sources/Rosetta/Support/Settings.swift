import Foundation

/// Plain preferences, backed directly by `UserDefaults` — same pattern as Parla's own
/// `Settings.swift`.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key: String {
        case sourceLocaleIdentifier = "rosetta.sourceLocaleIdentifier"
        case targetLanguage = "rosetta.targetLanguage"
    }

    struct LanguageOption: Identifiable, Hashable {
        /// Apple locale identifier — used to select which `SpeechTranscriber` model transcribes.
        let id: String
        /// Human-readable name shown in the picker.
        let label: String
    }

    /// Languages the Apple on-device speech engine can transcribe. The source picker is further
    /// narrowed at runtime to whichever of these are actually installed on this Mac.
    static let sourceLanguages: [LanguageOption] = [
        LanguageOption(id: "en_US", label: "English"),
        LanguageOption(id: "es_ES", label: "Spanish"),
        LanguageOption(id: "de_DE", label: "German"),
        LanguageOption(id: "fr_FR", label: "French"),
        LanguageOption(id: "it_IT", label: "Italian"),
        LanguageOption(id: "pt_BR", label: "Portuguese"),
        LanguageOption(id: "ja_JP", label: "Japanese"),
        LanguageOption(id: "ko_KR", label: "Korean"),
        LanguageOption(id: "zh_CN", label: "Chinese"),
        LanguageOption(id: "yue_CN", label: "Cantonese"),
    ]

    /// Translation targets — Claude handles the actual translation, so this list is not limited
    /// to what Apple's STT supports. Grouped into sections for the picker.
    static let targetLanguageGroups: [(title: String, languages: [String])] = [
        ("World Languages", [
            "Arabic", "Bengali", "Cantonese", "Chinese",
            "Czech", "Danish", "Dutch", "English",
            "Finnish", "French", "German", "Greek",
            "Hebrew", "Hindi", "Hungarian", "Indonesian",
            "Italian", "Japanese", "Korean", "Malay",
            "Norwegian", "Persian", "Polish", "Portuguese",
            "Romanian", "Russian", "Spanish", "Swahili",
            "Swedish", "Thai", "Turkish", "Ukrainian",
            "Urdu", "Vietnamese",
        ]),
        ("Fun & Fictional", [
            "Dothraki",
            "Klingon",
            "Black Speech of Mordor",
            "LinkedIn",
        ]),
    ]

    /// What language you're speaking. Explicit, not guessed — see the project history for why an
    /// auto-detect-by-running-every-locale-at-once scheme was tried and dropped: without Claude
    /// arbitrating between candidates (which needs a working translator to even run), the fallback
    /// showed whichever locale's *garbled* guess happened to produce non-empty text first, which is
    /// worse than just asking.
    static var sourceLocaleIdentifier: String {
        get { defaults.string(forKey: Key.sourceLocaleIdentifier.rawValue) ?? "en_US" }
        set { defaults.set(newValue, forKey: Key.sourceLocaleIdentifier.rawValue) }
    }

    static var targetLanguage: String {
        get { defaults.string(forKey: Key.targetLanguage.rawValue) ?? "Spanish" }
        set { defaults.set(newValue, forKey: Key.targetLanguage.rawValue) }
    }
}
