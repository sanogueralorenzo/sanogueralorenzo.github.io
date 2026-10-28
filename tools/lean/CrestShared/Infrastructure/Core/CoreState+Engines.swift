import Foundation

extension CoreState {
    // MARK: - Actions - Capabilities

    /// Whether the device offers `capability` anywhere a person can find a
    /// feature, such as a menu or a settings page: the default engine or an
    /// engine a page is open on supports it, or no engine has registered yet.
    /// Extension management remains available for an installed engine even
    /// before it starts; opening that feature explicitly starts its runtime.
    /// Whether a page can use it is its own engine's answer.
    func offers(_ capability: EngineCapability) -> Bool {
        engines?.offered.contains(capability) ?? true
    }

    /// Whether the engine new pages open on supports `capability`, which
    /// answers for a window before it shows a page. Every capability, until
    /// an engine registers.
    func defaultEngineSupports(_ capability: EngineCapability) -> Bool {
        guard let engines else { return true }
        return engines.engines.first(where: \.isDefault)?.capabilities.contains(capability) == true
    }

    // MARK: - Actions - Badges

    /// The engine whose badge the tab's icon wears: the one its page runs on,
    /// when the core badges that engine's pages. Nil for a tab without a page
    /// its engine holds or is making, and on a device where every page runs
    /// on one engine, which reads no page at all.
    func engineBadge(forTab tabID: UUID) -> EngineKind? {
        guard let badged = engines?.badged, !badged.isEmpty,
            let page = pages.values.first(where: { $0.tabID == tabID && $0.phase.holdsEnginePage })
        else { return nil }
        return badged.contains(page.engine) ? page.engine : nil
    }
}
