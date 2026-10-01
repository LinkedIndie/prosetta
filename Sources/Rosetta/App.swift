import SwiftUI

/// Entry point. Deliberately a plain SwiftUI `App`/`WindowGroup` rather than Parla's custom
/// `NSApplicationDelegate` + `NSWindowController` setup — that machinery exists there to toggle
/// between menu-bar-only and regular-app activation policy around a window that's usually closed.
/// Prosetta has no menu-bar mode and exactly one window that's open the whole time it's running, so
/// none of that is needed.
@main
struct ProsettaApp: App {
    @State private var model = AppModel()
    @State private var splashOpacity = 1.0
    @State private var splashVisible = true

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .overlay {
                    if splashVisible {
                        SplashView()
                            .opacity(splashOpacity)
                            .task {
                                try? await Task.sleep(for: .seconds(2.5))
                                withAnimation(.easeIn(duration: 0.8)) { splashOpacity = 0 }
                                try? await Task.sleep(for: .seconds(0.8))
                                splashVisible = false
                            }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
