import Foundation

/// Every window's sidebar layout on this device, kept in `defaults`, or in
/// memory without them.
///
/// The set limits itself: every unrestored iOS scene comes back under a fresh
/// window identity, so each force-quit would otherwise leave a record behind.
/// Sixteen is comfortably more windows than iPadOS shows at once, and the
/// window used longest ago is forgotten first.
@MainActor
final class BrowserWindowLayouts {
    // MARK: - Variables

    /// Where earlier releases kept each window's selection and layout, which
    /// the core carries into its device store once.
    static let legacyRecordsKey = "crest.windows.v1"
    static let maximumCount = 16
    private static let key = "crest.windowLayouts.v1"

    private let defaults: UserDefaults?
    /// Oldest use first.
    private var layouts: [BrowserWindowState]

    // MARK: - Initializers

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        layouts =
            defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([BrowserWindowState].self, from: $0) }
            ?? []
    }

    // MARK: - Actions - Layouts

    func layout(for id: UUID) -> BrowserWindowState? {
        layouts.first { $0.id == id }
    }

    /// Stores one window's layout as the most recently used.
    func save(_ layout: BrowserWindowState) {
        layouts.removeAll { $0.id == layout.id }
        layouts.append(layout)
        if layouts.count > Self.maximumCount { layouts.removeFirst(layouts.count - Self.maximumCount) }
        write()
    }

    func remove(id: UUID) {
        guard layouts.contains(where: { $0.id == id }) else { return }
        layouts.removeAll { $0.id == id }
        write()
    }

    /// Hands the records an earlier release kept to `core`, which carries what
    /// each window showed into its device store once, and keeps the layouts
    /// they held. A core that adopted them before answers nothing.
    func adoptLegacyRecords(into core: CrestCore) {
        let changes: [Change]
        do {
            changes = try core.send(AdoptWindowRecords(records: defaults?.data(forKey: Self.legacyRecordsKey)))
        } catch {
            DiagnosticLog.windows.error("The core could not adopt the window records: \(DiagnosticLog.describe(error))")
            return
        }
        for case .windowRecordsAdopted(let adopted) in changes {
            for layout in adopted.layouts where self.layout(for: layout.windowID) == nil {
                save(
                    BrowserWindowState(
                        id: layout.windowID, sidebarWidth: layout.sidebarWidth,
                        sidebarIsPresented: layout.sidebarIsPresented))
            }
        }
    }

    private func write() {
        guard let defaults, let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
