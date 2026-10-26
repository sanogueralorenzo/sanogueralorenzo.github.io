import Foundation

struct BrowserWebKitFeatureFlagGroup: Identifiable, Equatable {
    let category: BrowserWebKitFeatureCategory
    let flags: [BrowserWebKitFeatureFlag]

    var id: Int { category.id }
}

struct BrowserWebKitFeatureFlagFilter: Equatable {
    var searchText = ""
    var status: BrowserWebKitFeatureStatus?
    var category: BrowserWebKitFeatureCategory?
    var showsOnlyChanged = false

    func groups(
        from flags: [BrowserWebKitFeatureFlag],
        overrides: [String: BrowserWebKitFeatureFlagOverride]
    ) -> [BrowserWebKitFeatureFlagGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredFlags = flags.filter { flag in
            matches(flag, query: query, overrides: overrides)
        }
        return Dictionary(grouping: filteredFlags, by: \.category)
            .map { category, flags in
                BrowserWebKitFeatureFlagGroup(
                    category: category,
                    flags: flags.sorted(by: Self.sortFlags)
                )
            }
            .sorted(by: Self.sortGroups)
    }

    private func matches(
        _ flag: BrowserWebKitFeatureFlag,
        query: String,
        overrides: [String: BrowserWebKitFeatureFlagOverride]
    ) -> Bool {
        guard status == nil || flag.status == status else { return false }
        guard category == nil || flag.category == category else { return false }
        guard !showsOnlyChanged || overrides[flag.key] != nil else { return false }
        return query.isEmpty
            || flag.searchText.localizedCaseInsensitiveContains(query)
    }

    private static func sortFlags(
        _ lhs: BrowserWebKitFeatureFlag,
        _ rhs: BrowserWebKitFeatureFlag
    ) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func sortGroups(
        _ lhs: BrowserWebKitFeatureFlagGroup,
        _ rhs: BrowserWebKitFeatureFlagGroup
    ) -> Bool {
        lhs.category.title.localizedStandardCompare(rhs.category.title)
            == .orderedAscending
    }
}
