import AVFoundation
import Foundation
import Speech

/// Streaming on-device (or Apple-server) transcription via `SFSpeechRecognizer` — the same engine
/// macOS system Dictation uses. Unlike the macOS 26 `SpeechAnalyzer`/`SpeechTranscriber` API,
/// `SFSpeechRecognizer` works for all Apple-supported locales without requiring per-language model
/// downloads: when an on-device model isn't present it transparently routes to Apple's speech
/// servers, exactly as Dictation does in TextEdit and other system apps.
actor SpeechEngine {

    struct Update: Sendable {
        let text: String
        let isVolatile: Bool
        let newlyFinalized: String?
    }

    /// The write end of the audio input stream. Thread-safe: `send` is called from the audio
    /// capture callback, `finish` from the main actor.
    final class Input: @unchecked Sendable {
        private let request: SFSpeechAudioBufferRecognitionRequest

        init(_ request: SFSpeechAudioBufferRecognitionRequest) {
            self.request = request
        }

        func send(_ buffer: AVAudioPCMBuffer) {
            request.append(buffer)
        }

        func finish() {
            request.endAudio()
        }
    }

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestText = ""
    private var isDone = false
    private var pendingFinish: CheckedContinuation<String, Never>?

    private(set) var locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    /// 16 kHz mono is the canonical format for speech recognition; `SFSpeechRecognizer` will
    /// accept other rates but this avoids any internal resampling.
    static func preferredFormat(for locale: Locale) async -> AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    }

    // MARK: - Session

    func start() async throws -> (updates: AsyncThrowingStream<Update, Error>, input: Input) {
        stop()
        latestText = ""
        isDone = false

        let rec = SFSpeechRecognizer(locale: locale)
        guard let rec, rec.isAvailable else {
            throw EngineError.recognizerUnavailable(locale.identifier)
        }
        recognizer = rec

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // allow Apple servers when on-device model absent
        request.addsPunctuation = true

        let (updates, updateContinuation) = AsyncThrowingStream<Update, Error>.makeStream(
            bufferingPolicy: .unbounded
        )

        recognitionTask = rec.recognitionTask(with: request) { [weak self] result, error in
            // Extract Sendable values before hopping to the actor — SFSpeechRecognitionResult
            // is not Sendable, so we can't pass it across the isolation boundary directly.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { await self?.handle(text: text, isFinal: isFinal, error: error, to: updateContinuation) }
        }

        let input = Input(request)
        Log.speech.info("started SFSpeechRecognizer for \(self.locale.identifier)")
        return (updates, input)
    }

    private func handle(
        text: String?,
        isFinal: Bool,
        error: Error?,
        to continuation: AsyncThrowingStream<Update, Error>.Continuation
    ) {
        if let text {
            latestText = text
            continuation.yield(Update(text: text, isVolatile: !isFinal, newlyFinalized: isFinal ? text : nil))
        }

        let isTerminal = isFinal || error != nil

        if let error {
            let code = (error as NSError).code
            // 203 = no speech detected, 301 = audio interrupted, 216 = recognition cancelled — benign.
            if code == 203 || code == 301 || code == 216 {
                continuation.finish()
            } else {
                Log.speech.error("recognition error: \(error.localizedDescription)")
                continuation.finish(throwing: error)
            }
        } else if isFinal {
            continuation.finish()
        }

        if isTerminal {
            isDone = true
            pendingFinish?.resume(returning: latestText)
            pendingFinish = nil
        }
    }

    /// Waits for the active recognition task to produce its final result. Bounded to 5 s so a
    /// wedged recognizer can't leave the app stuck forever.
    func finish() async -> String {
        if isDone { return latestText }

        return await withTaskGroup(of: String.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                    Task { await self.storeContinuation(cont) }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return await self.latestText
            }
            let first = await group.next() ?? latestText
            group.cancelAll()
            return first
        }
    }

    private func storeContinuation(_ cont: CheckedContinuation<String, Never>) {
        if isDone {
            cont.resume(returning: latestText)
        } else {
            pendingFinish = cont
        }
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        isDone = true
        pendingFinish?.resume(returning: latestText)
        pendingFinish = nil
    }

    // MARK: - Errors

    enum EngineError: LocalizedError {
        case recognizerUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable(let id):
                "Speech recognition is not available for \(id). Check System Settings → Keyboard → Dictation."
            }
        }
    }
}
