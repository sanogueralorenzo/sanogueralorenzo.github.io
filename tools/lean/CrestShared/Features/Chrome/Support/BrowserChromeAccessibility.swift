import Foundation

/// Produces stable spoken state for Crest's custom browser chrome. The views
/// remain native controls; this policy only supplies values and one-step Space
/// navigation that SwiftUI cannot infer from the custom horizontal pager.
enum BrowserChromeAccessibility {
    @MainActor
    static func spaceValue(
        spaces: [SpaceModel],
        selectedSpaceID: UUID
    ) -> String {
        guard let index = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else {
            return "No Space selected"
        }
        return "\(spaces[index].settings.name), \(index + 1) of \(spaces.count)"
    }

    @MainActor
    static func adjacentSpaceID(
        spaces: [SpaceModel],
        selectedSpaceID: UUID,
        direction: BrowserChromeAccessibilityDirection
    ) -> UUID? {
        guard let index = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else {
            return nil
        }
        let targetIndex =
            switch direction {
            case .previous:
                index - 1
            case .next:
                index + 1
            }
        guard spaces.indices.contains(targetIndex) else { return nil }
        return spaces[targetIndex].id
    }

    static func tabValue(isLoaded: Bool) -> String {
        isLoaded ? "Loaded" : "Not loaded"
    }

    static func folderValue(isExpanded: Bool) -> String {
        isExpanded ? "Expanded" : "Collapsed"
    }

    static func countValue(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        let boundedCount = max(0, count)
        return "\(boundedCount) \(boundedCount == 1 ? singular : plural)"
    }
}
