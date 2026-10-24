#if DEBUG
    import Foundation

    /// What a test reads back from a seed it built, in the words it reads a
    /// published Space in.
    extension SpaceState.Seed {
        // MARK: - Variables

        var pinnedTabs: [TabState.Seed] { tabs.filter { $0.placement == .pinned } }
        var savedTabs: [TabState.Seed] { tabs.filter { $0.placement == .saved } }
        var currentTabs: [TabState.Seed] { tabs.filter { !$0.placement.isDurable } }

        // MARK: - Actions - Reading

        /// Whether the seed holds the tab open.
        func contains(_ tabID: UUID) -> Bool {
            tabs.contains { $0.id == tabID }
        }
    }
#endif
