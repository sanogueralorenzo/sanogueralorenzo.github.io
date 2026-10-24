/// How the person asked to reload a page. Each mode carries what it does to
/// the page's engine.
struct BrowserPageReloadMode: Hashable, Sendable {
    // MARK: - Static Variables

    /// Reload, or stop a page still loading.
    static let standard = BrowserPageReloadMode(name: "standard") { page, isLoading in
        if isLoading { page.stop() } else { page.reload(bypassingCache: false) }
    }
    /// Reload from the origin, bypassing the cache, even while loading.
    static let fromOrigin = BrowserPageReloadMode(name: "fromOrigin") { page, _ in
        page.reload(bypassingCache: true)
    }

    // MARK: - Variables

    let name: String
    private let perform: @MainActor @Sendable (EnginePage, _ isLoading: Bool) -> Void

    // MARK: - Initializers

    private init(name: String, perform: @escaping @MainActor @Sendable (EnginePage, _ isLoading: Bool) -> Void) {
        self.name = name
        self.perform = perform
    }

    // MARK: - Actions - Reloading

    /// Reloads `page` as this mode asks, given whether it is still loading.
    @MainActor func perform(on page: EnginePage, isLoading: Bool) {
        perform(page, isLoading)
    }

    // MARK: - Equatable

    static func == (lhs: BrowserPageReloadMode, rhs: BrowserPageReloadMode) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
