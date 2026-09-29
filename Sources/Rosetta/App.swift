import SwiftUI

/// Entry point. Deliberately a plain SwiftUI `App`/`WindowGroup` rather than Parla's custom
/// `NSApplicationDelegate` + `NSWindowController` setup — that machinery exists there to toggle
/// between menu-bar-only and regular-app activation policy around a window that's usually closed.
/// Prosetta has no menu-bar mode and exactly one window that's open the whole time it's running, so
/// none of that is needed.
@main
struct ProsettaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
