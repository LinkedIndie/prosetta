import AVFoundation
import Foundation

/// Converts microphone buffers into the format a speech analyzer asked for. Copied from Parla's own
/// `AudioPipeline.swift` — the microphone's native format rarely matches what the analyzer wants,
/// and a mismatched buffer doesn't throw, it just produces silence or nonsense that then reads as
/// an accuracy problem.
final class FormatConverter {

    private let target: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(target: AVAudioFormat?) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target else { return buffer }
        if buffer.format == target { return buffer }

        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
            Log.audio.info("converting \(buffer.format.sampleRate)Hz → \(target.sampleRate)Hz")
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        if let error {
            Log.audio.error("conversion failed: \(error.localizedDescription)")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }
}
