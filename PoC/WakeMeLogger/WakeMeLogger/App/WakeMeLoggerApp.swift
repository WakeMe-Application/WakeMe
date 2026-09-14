import SwiftUI

@main
struct WakeMeLoggerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            RideRecorder.shared.logAppState(String(describing: phase))
        }
    }
}
