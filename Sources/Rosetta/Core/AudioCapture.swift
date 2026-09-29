import AVFoundation
import Foundation

/// Microphone capture. Copied near-verbatim from Parla's own `AudioCapture.swift` — this class has
/// no Accessibility or hotkey coupling at all, just an `AVAudioEngine` tap fanned out to whoever is
/// listening.
final class AudioCapture: @unchecked Sendable {

    enum Mode {
        /// Microphone opens on record-button press. Indicator shows only while recording.
        case onDemand
        /// Microphone stays open with a pre-roll buffer, so the first syllable is never clipped.
        case continuous
    }

    private static let preRollSeconds = 0.3

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let mode: Mode

    private var ring: [AVAudioPCMBuffer] = []
    private var ringDuration: Double = 0

    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var tapInstalled = false
    private var graphPrepared = false

    /// Most recent RMS level, 0…1, for the level meter.
    private(set) var level: Float = 0

    private var lastBufferAt: Date?

    /// Fires when the input device is pulled out from under an in-flight recording.
    var onStreamInterrupted: (() -> Void)?

    private var configChangeObserver: NSObjectProtocol?
    private var stallTimer: Timer?
    private static let stallThreshold: TimeInterval = 1.5

    init(mode: Mode = .onDemand) {
        self.mode = mode
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVAudioEngineConfigurationChangeNotification"),
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
    }

    private func handleConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Log.audio.warning("audio hardware reconfigured mid-session — tap is stale, marking for rebuild")

            let wasCapturing = self.lock.withLock { self.sink != nil }

            if self.tapInstalled {
                self.engine.inputNode.removeTap(onBus: 0)
                self.tapInstalled = false
            }
            self.graphPrepared = false

            if wasCapturing {
                self.onStreamInterrupted?()
            }
        }
    }

    // MARK: - Lifecycle

    /// Prepares everything that can be prepared without starting capture, so the record button's
    /// first press doesn't pay the ~500ms cold-open cost of `engine.start()`.
    func prepare() throws {
        switch mode {
        case .continuous:
            try openMicrophone()
        case .onDemand:
            try prepareGraph()
            Log.audio.info("graph prepared — mic opens on record, indicator stays off until then")
        }
    }

    private func prepareGraph() throws {
        guard !graphPrepared else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw AudioError.noInputDevice
        }

        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.receive(buffer)
            }
            tapInstalled = true
        }

        engine.prepare()
        graphPrepared = true
        Log.audio.debug("graph prepared at \(format.sampleRate)Hz")
    }

    func shutdown() {
        stallTimer?.invalidate()
        stallTimer = nil
        closeMicrophone()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        graphPrepared = false
        lock.withLock {
            ring.removeAll()
            ringDuration = 0
            sink = nil
            lastBufferAt = nil
        }
        level = 0
    }

    // MARK: - Recording

    func beginUtterance(_ handler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if mode == .onDemand {
            try openMicrophone()
        }

        let preRoll: [AVAudioPCMBuffer] = lock.withLock {
            sink = handler
            lastBufferAt = Date()
            guard mode == .continuous else { return [] }
            let captured = ring
            ring.removeAll()
            ringDuration = 0
            return captured
        }

        if !preRoll.isEmpty {
            Log.audio.debug("utterance began with \(preRoll.count) pre-roll buffers")
            for buffer in preRoll { handler(buffer) }
        }

        startStallTimer()
    }

    func endUtterance() {
        stallTimer?.invalidate()
        stallTimer = nil
        lock.withLock {
            sink = nil
            lastBufferAt = nil
        }
        if mode == .onDemand {
            closeMicrophone()
        }
        level = 0
    }

    private func startStallTimer() {
        stallTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func checkForStall() {
        let stalled: Bool = lock.withLock {
            guard sink != nil, let lastBufferAt else { return false }
            return Date().timeIntervalSince(lastBufferAt) > Self.stallThreshold
        }
        guard stalled else { return }

        lock.withLock { lastBufferAt = nil }
        stallTimer?.invalidate()
        stallTimer = nil
        Log.audio.warning("no audio buffer for \(Self.stallThreshold)s during an active utterance — stream stalled")
        onStreamInterrupted?()
    }

    // MARK: - Device

    private func openMicrophone() throws {
        guard !engine.isRunning else { return }
        try prepareGraph()

        let started = Date()
        try engine.start()
        let ms = Date().timeIntervalSince(started) * 1000
        Log.audio.info("mic open in \(ms)ms")
    }

    private func closeMicrophone() {
        guard engine.isRunning else { return }
        engine.stop()
        Log.audio.info("mic closed (graph retained)")
    }

    // MARK: - Audio thread

    private func receive(_ buffer: AVAudioPCMBuffer) {
        level = Self.rms(of: buffer)

        let handler: ((AVAudioPCMBuffer) -> Void)? = lock.withLock {
            if let sink {
                lastBufferAt = Date()
                return sink
            }
            guard mode == .continuous else { return nil }

            ring.append(buffer)
            ringDuration += Double(buffer.frameLength) / buffer.format.sampleRate
            while ringDuration > Self.preRollSeconds, let oldest = ring.first {
                ringDuration -= Double(oldest.frameLength) / oldest.format.sampleRate
                ring.removeFirst()
            }
            return nil
        }

        handler?(buffer)
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        let count = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<count {
            let sample = samples[i]
            sum += sample * sample
        }
        let value = (sum / Float(count)).squareRoot()
        guard value.isFinite else {
            Log.audio.warning("non-finite RMS from input buffer — clamped to 0")
            return 0
        }
        return min(max(value, 0), 1)
    }

    enum AudioError: LocalizedError {
        case noInputDevice

        var errorDescription: String? {
            switch self {
            case .noInputDevice:
                "No microphone is available."
            }
        }
    }
}
