import SwiftUI
import OnePercentCore

@main
struct OnePercentiOSApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TodayView(model: model, store: model.store)
                // Texts are looked up as views are built, so a language change rebuilds them.
                .id(model.language)
                .preferredColorScheme(.dark)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.becameActive() }
                }
        }
    }
}
