import Foundation

/// The four screens that share the space under the progress bar.
enum IslandPage: Equatable {
    case goals
    case stats
    case settings
    case detail(UUID)

    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }
}
