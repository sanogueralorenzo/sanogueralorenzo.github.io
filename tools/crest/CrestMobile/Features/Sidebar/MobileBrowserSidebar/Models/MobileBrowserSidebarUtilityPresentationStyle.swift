/// Where the archive, history, and downloads lists come up.
///
/// A sidebar standing beside a page has room to swap its own body for the list
/// and keeps the reader in place. A sidebar that *is* the screen has nowhere to
/// put a list except over itself, so it presents a sheet and leaves its tabs
/// underneath. This is the choice each placement makes, not a device: the same
/// build makes it both ways in one session.
struct MobileBrowserSidebarUtilityPresentationStyle: Equatable, Sendable {
    // MARK: - Static Variables

    static let inline = MobileBrowserSidebarUtilityPresentationStyle(
        name: "inline", presentsHistory: { $0.utilityPresentation.present(.history) })
    static let sheet = MobileBrowserSidebarUtilityPresentationStyle(
        name: "sheet", presentsHistory: { $0.presentSpaceSheet(.history) })

    // MARK: - Variables

    let name: String
    private let presentsHistory: @MainActor @Sendable (MobileBrowserSidebarSurface) -> Void

    // MARK: - Initializers

    private init(name: String, presentsHistory: @escaping @MainActor @Sendable (MobileBrowserSidebarSurface) -> Void) {
        self.name = name
        self.presentsHistory = presentsHistory
    }

    // MARK: - Actions - Lists

    /// Brings the history list up where this style puts lists.
    @MainActor
    func presentHistory(from surface: MobileBrowserSidebarSurface) {
        presentsHistory(surface)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
