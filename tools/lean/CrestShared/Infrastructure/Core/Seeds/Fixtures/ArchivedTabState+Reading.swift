#if DEBUG
    import Foundation

    extension ArchivedTabState.Seed {
        // MARK: - Variables

        /// The archived tab's identity.
        var id: UUID { tab.id }
    }
#endif
