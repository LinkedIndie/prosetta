// swift-tools-version: 6.2
import PackageDescription

// Prosetta — a small, standalone translation-dictation window for macOS.
//
// Deliberately dependency-free: it needs nothing beyond Apple's own frameworks (Speech, AVFoundation,
// SwiftUI) and shells out to the already-installed `claude` CLI as a subprocess for translation,
// rather than linking anything. Keeping this package free of third-party dependencies is what makes
// its build fast and its footprint small — see the project's own design notes for why.
let package = Package(
    name: "Prosetta",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Prosetta",
            path: "Sources/Rosetta",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
