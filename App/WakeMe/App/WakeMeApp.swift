import SwiftUI

@main
struct WakeMeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(DS.primary)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HomeView()
            .sheet(item: $model.setupDraft, onDismiss: { model.presentPendingTrip() }) { draft in
                TripSetupView(draft: draft)
            }
            .sheet(isPresented: $model.showSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $model.session) { session in
                TripView(session: session)
            }
            .fullScreenCover(isPresented: $model.showOnboarding) {
                OnboardingView()
            }
            .alert(
                model.routeNotice ?? "",
                isPresented: Binding(get: { model.routeNotice != nil }, set: { if !$0 { model.routeNotice = nil } })
            ) {
                Button("확인", role: .cancel) {}
            }
    }
}
