import Foundation

@MainActor
enum BrowserCommandPalettePreviewFixture {
    static let selectedTabID = uuid(finalByte: 0x11)

    static let currentSpace = SpaceState.Seed(
        id: uuid(finalByte: 0x21),
        profileID: uuid(finalByte: 0x31),
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        tabs: [
            TabState.Seed(
                id: selectedTabID,
                title: "Crest",
                url: url("https://crestbrowser.com"),
                placement: .current,
                lastActivatedAt: date(offset: 400)
            ),
            TabState.Seed(
                id: uuid(finalByte: 0x12),
                title: "Swift Evolution",
                url: url("https://www.swift.org/swift-evolution"),
                placement: .current,
                lastActivatedAt: date(offset: 300)
            ),
            TabState.Seed(
                id: uuid(finalByte: 0x13),
                title: "GitHub",
                url: url("https://github.com"),
                placement: .pinned,
                lastActivatedAt: date(offset: 200)
            ),
        ],
        history: [
            HistoryEntryState(
                id: uuid(finalByte: 0x41),
                url: url("https://forums.swift.org"),
                title: "Swift Forums",
                firstVisitedAt: date(offset: 100),
                lastVisitedAt: date(offset: 500),
                visitCount: 7
            )
        ]
    )

    static let registry = BrowserCommandPaletteCommandRegistry(
        commands: [.newWindow, .showHistory, .showDownloads, .toggleSidebar],
        shortcut: { command in
            guard command == .showHistory else { return nil }
            return BrowserShortcut(
                key: .character("y"),
                modifiers: [.command, .shift]
            )
        },
        perform: { _ in }
    )

    /// A window over the preview Space on a memory-only core.
    static let browser = BrowserStore(
        seed: SessionState.Seed(spaces: [currentSpace]),
        images: Dictionary(uniqueKeysWithValues: currentSpace.tabs.map { ($0.id, faviconData) }),
        showing: currentSpace.id)

    static var space: SpaceModel? { browser.spaceModel(currentSpace.id) }

    static let google = SearchProvider(
        name: BuiltInSearchProvider.google.name, title: BuiltInSearchProvider.google.title, kind: .engine,
        shortcuts: BuiltInSearchProvider.google.shortcuts, searchTemplate: "https://www.google.com/search?q=%s",
        suggestionTemplate: nil, color: BuiltInSearchProvider.google.color, logo: BuiltInSearchProvider.google.logo,
        builtIn: .google, customID: nil, site: "google.com")

    static let intentRow = PaletteRow(
        kind: .search, title: "Search Google", subtitle: "swift", symbol: PaletteRowKind.search.symbol,
        subjectID: nil, tabID: nil, address: "https://www.google.com/search?q=swift", command: nil, provider: google,
        settingsPage: nil, scope: nil, reason: nil)

    static let tabRow = PaletteRow(
        kind: .tab, title: "Swift Evolution", subtitle: "www.swift.org", symbol: PaletteRowKind.tab.symbol,
        subjectID: nil,
        tabID: uuid(finalByte: 0x12), address: nil, command: nil, provider: nil,
        settingsPage: nil, scope: nil, reason: .recentlyUsed)

    static let commandRow = PaletteRow(
        kind: .command, title: "Show History", subtitle: "View", symbol: ShortcutCommand.showHistory.symbol,
        subjectID: nil,
        tabID: nil, address: nil, command: .showHistory, provider: nil,
        settingsPage: nil, scope: nil, reason: nil)

    static let intentItem = BrowserCommandPaletteItem(index: 0, row: intentRow)
    static let tabItem = BrowserCommandPaletteItem(index: 1, row: tabRow)
    static let commandItem = BrowserCommandPaletteItem(index: 2, row: commandRow)

    static func model(query: String) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            browser: browser,
            space: space,
            selectedTabID: selectedTabID,
            initialQuery: query,
            commands: registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, _, _ in true },
            dismiss: {}
        )
    }

    private static func url(_ value: String) -> URL {
        URL(
            string: value.replacingOccurrences(
                of: "https://",
                with: "crest-preview://"
            )
        ) ?? URL(fileURLWithPath: "/command-palette-preview")
    }

    private static let faviconData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0x60, 0x68, 0xF8, 0xCF,
        0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
        0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])

    private static func date(offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }

    private static func uuid(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x50, 0x52, 0x45, finalByte
            ))
    }
}
