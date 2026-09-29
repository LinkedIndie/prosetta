import Foundation
import OSLog

/// Logging, to two places at once — the same pattern Parla uses, for the same reason: `OSLog` is
/// structured and cheap, but proved unreadable from outside the app during development, so a plain
/// text file backs it up. See `~/Library/Application Support/Prosetta/prosetta.log`.
enum Log {
    private static let subsystem = "com.wanggregory.prosetta"

    static let audio     = Category(os: Logger(subsystem: subsystem, category: "audio"),     name: "audio")
    static let speech     = Category(os: Logger(subsystem: subsystem, category: "speech"),     name: "speech")
    static let translate = Category(os: Logger(subsystem: subsystem, category: "translate"), name: "translate")
    static let app        = Category(os: Logger(subsystem: subsystem, category: "app"),        name: "app")

    struct Category {
        let os: Logger
        let name: String

        func debug(_ message: String) {
            os.debug("\(message)")
            FileLog.write(level: "DEBUG", category: name, message: message)
        }

        func info(_ message: String) {
            os.info("\(message)")
            FileLog.write(level: "INFO", category: name, message: message)
        }

        func warning(_ message: String) {
            os.warning("\(message)")
            FileLog.write(level: "WARN", category: name, message: message)
        }

        func error(_ message: String) {
            os.error("\(message)")
            FileLog.write(level: "ERROR", category: name, message: message)
        }
    }
}

/// Append-only text log, written synchronously so the last line written is always the last thing
/// that happened — see Parla's own `Log.swift` for the incident that established this.
enum FileLog {
    private static let lock = NSLock()

    private static let url: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "Prosetta", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "prosetta.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(level: String, category: String, message: String) {
        let line = "\(formatter.string(from: Date())) \(level.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func startSession() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        write(level: "INFO", category: "app", message: "───── session start \(stamp) ─────")
    }

    static var path: String { url.path }
}
