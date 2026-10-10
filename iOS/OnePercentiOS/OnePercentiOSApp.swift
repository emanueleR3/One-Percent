import SwiftUI
import OnePercentCore

@main
struct OnePercentiOSApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The system may start the app in the background for a moment; the handler has to be
        // registered before launch finishes, so it cannot wait for a screen.
        BackgroundRefresh.register { await AppModel.shared.backgroundRefresh() }
    }

    var body: some Scene {
        WindowGroup {
            TodayView(model: model, store: model.store, focus: model.focus)
                // Texts are looked up as views are built, so a language change rebuilds them.
                .id(model.language)
                .preferredColorScheme(.dark)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.becameActive() }
                    if phase == .background { model.enteredBackground() }
                }
        }
    }
}
