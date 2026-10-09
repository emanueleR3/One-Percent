import Foundation
import ServiceManagement

/// Wraps `SMAppService` so Settings can offer "Launch at login". Registration only works for a
/// real app bundle, so failures are surfaced as text instead of crashing a development build.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't change login item: \(error.localizedDescription)"
        }
        refresh()
    }
}
