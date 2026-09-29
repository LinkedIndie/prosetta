import AVFoundation
import Foundation
import Speech

/// Owns one `SpeechEngine` per source language the user has ever selected, reusing each across
/// recordings so switching back to a language you've already used doesn't pay a cold-start cost.
///
/// Deliberately single-locale-at-a-time now, not a parallel candidate fan-out: an earlier version
/// ran every supported locale simultaneously and asked Claude to arbitrate which one was real
/// speech, specifically to avoid a source-language picker. In practice that meant a translator
/// outage (no CLI, no API key) also broke transcription — with no arbitration, the fallback showed
/// whichever locale's garbled guess happened to produce non-empty text first, which is worse than
/// just asking which language you're speaking. An explicit picker is simpler, faster (one engine
/// instead of ten), and never shows a garbled guess instead of what you actually said.
actor TranscriptionManager {

    private var engines: [String: SpeechEngine] = [:]
    private var activeLocaleID: String?

    func preferredFormat(for localeID: String) async -> AVAudioFormat? {
        await SpeechEngine.preferredFormat(for: Locale(identifier: localeID))
    }

    func beginUtterance(localeID: String) async throws -> SpeechEngine.Input {
        activeLocaleID = localeID
        let engine = engines[localeID] ?? SpeechEngine(locale: Locale(identifier: localeID))
        engines[localeID] = engine
        let (_, input) = try await engine.start()
        return input
    }

    /// Waits for the active locale's engine to finish. The caller must have already called
    /// `.finish()` on the `SpeechEngine.Input` returned by `beginUtterance` — closing the input is
    /// what lets the analyzer's results stream end.
    func finish() async -> String {
        guard let localeID = activeLocaleID, let engine = engines[localeID] else { return "" }
        activeLocaleID = nil
        return await engine.finish()
    }
}
