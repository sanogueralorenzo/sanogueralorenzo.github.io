import Foundation

/// Global interface choices use the same defaults domain as the rest of the app.
/// Space color strength travels separately with the existing branding payload.
@MainActor
enum BrowserFolderAppearancePreference {
    static let alwaysVisibleKey = "crest.folders.alwaysShowHighlights"
    static let showsTabCountsKey = "crest.folders.showsTabCounts"
    static let showsBordersKey = "crest.folders.showsBorders"
    static let iconOnlyKey = "crest.folders.iconOnly"
    static let tintsTitleKey = "crest.folders.tintsTitle"

    static let defaults: UserDefaults = {
        let environment = BrowserLaunchEnvironment.current
        guard environment.requiresIsolation else { return .standard }
        let id = environment.persistentIsolationID ?? "ephemeral-\(UUID().uuidString)"
        return UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: id))!
    }()
}
