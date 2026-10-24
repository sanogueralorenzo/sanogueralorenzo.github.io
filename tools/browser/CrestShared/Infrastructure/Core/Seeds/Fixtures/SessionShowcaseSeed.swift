import Foundation

/// The session screenshots and the showcase show: a Work Space with pinned,
/// saved and split current tabs and an archive, and a Personal one, each
/// page drawn in place from its own markup.
enum SessionShowcaseSeed {
    // MARK: - Actions - Building

    static func make() -> SessionState.Seed {
        SessionState.Seed(spaces: [makeWorkSpace(), makePersonalSpace()])
    }

    private static func makeWorkSpace() -> SpaceState.Seed {
        let folder = FolderState.Seed(title: "Launch Atlas", symbol: "folder.fill")
        let splitGroupID = UUID()
        let secondSplitGroupID = UUID()
        let tabs = [
            tab("Brief", page(.work, title: "Brief", activeCard: 0), "🧭", .pinned),
            tab("Projects", page(.work, title: "Projects", activeCard: 1), "📐", .pinned),
            tab("Calendar", page(.work, title: "Calendar", activeCard: 2), "📅", .pinned),
            tab("Notes", page(.work, title: "Notes", activeCard: 3), "✍️", .pinned),
            tab("Audience research", page(.work, title: "Audience research", activeCard: 1), "🔬", .saved, folder.id),
            tab("Launch plan", page(.work, title: "Launch plan", activeCard: 2), "🚩", .saved, folder.id),
            tab("Design review", page(.work, title: "Design review", activeCard: 3), "🎨", .saved, folder.id),
            tab(
                "Monday overview", page(.work, title: "Monday overview", activeCard: 0), "✨", .current,
                splitGroupID: splitGroupID),
            tab(
                "Launch notes", page(.work, title: "Launch notes", activeCard: 3), "🗒️", .current,
                splitGroupID: splitGroupID),
            tab(
                "Decision log", page(.work, title: "Decision log", activeCard: 1), "🧠", .current,
                splitGroupID: secondSplitGroupID),
            tab(
                "Launch checklist", page(.work, title: "Launch checklist", activeCard: 2), "✅", .current,
                splitGroupID: secondSplitGroupID),
        ]
        let archivedTabs = [
            archivedTab(
                "Remote launch brief", page(.work, title: "Remote launch brief", activeCard: 0), "☁️",
                reason: .synced, secondsAgo: 90),
            archivedTab(
                "Completed design review", page(.work, title: "Completed design review", activeCard: 3), "🎨",
                reason: .closed, secondsAgo: 240),
            archivedTab(
                "Idle research notes", page(.work, title: "Idle research notes", activeCard: 1), "📦",
                reason: .autoCleanup, secondsAgo: 540),
        ]
        return SpaceState.Seed(
            name: "Work", symbol: "hammer.fill", accent: .indigo, branding: SpaceAccent.rose.house, folders: [folder],
            tabs: tabs, archivedTabs: archivedTabs)
    }

    private static func makePersonalSpace() -> SpaceState.Seed {
        let folder = FolderState.Seed(title: "Weekend Plans", symbol: "folder.fill")
        let tabs = [
            tab("Home", page(.personal, title: "Home", activeCard: 0), "🏡", .pinned),
            tab("Trips", page(.personal, title: "Trips", activeCard: 1), "🗺️", .pinned),
            tab("Recipes", page(.personal, title: "Recipes", activeCard: 2), "🍲", .pinned),
            tab("Reading", page(.personal, title: "Reading", activeCard: 3), "📚", .pinned),
            tab("Cabin ideas", page(.personal, title: "Cabin ideas", activeCard: 1), "🏔️", .saved, folder.id),
            tab("Garden notes", page(.personal, title: "Garden notes", activeCard: 2), "🌱", .saved, folder.id),
            tab("Sunday reading", page(.personal, title: "Sunday reading", activeCard: 3), "📖", .saved, folder.id),
            tab("A slower Saturday", page(.personal, title: "A slower Saturday", activeCard: 0), "☀️", .current),
        ]
        return SpaceState.Seed(
            name: "Personal", symbol: "leaf.fill", accent: .teal, branding: SpaceAccent.indigo.house, folders: [folder],
            tabs: tabs)
    }

    private static func page(
        _ style: BrowserShowcasePageStyle,
        title: String,
        activeCard: Int
    ) -> URL {
        let cardMarkup = style.cards.enumerated().map { index, card in
            """
            <article class="card \(index == activeCard ? "active" : "")">
              <span>0\(index + 1)</span><h2>\(card.0)</h2><p>\(card.1)</p>
            </article>
            """
        }.joined()
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title><style>
            *{box-sizing:border-box}body{margin:0;padding:clamp(32px,6vw,84px);color:\(style.ink);background:\(style.background);font-family:-apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1100px;margin:auto}.kicker{font-size:11px;font-weight:800;letter-spacing:.2em}.hero{display:grid;grid-template-columns:1.2fr .8fr;gap:40px;align-items:end;margin:8vh 0 7vh}.hero h1{margin:0;font:500 clamp(52px,8vw,100px)/.88 ui-serif,Georgia,serif;letter-spacing:-.055em}.hero p{max-width:420px;margin:0 0 8px;font-size:18px;line-height:1.55;color:color-mix(in srgb,\(style.ink) 65%,transparent)}.rule{height:10px;background:linear-gradient(90deg,\(style.accent) 0 56%,\(style.warm) 56%)}.grid{display:grid;grid-template-columns:repeat(4,1fr);border-top:1px solid color-mix(in srgb,\(style.ink) 20%,transparent);border-left:1px solid color-mix(in srgb,\(style.ink) 20%,transparent)}.card{min-height:185px;padding:24px;border-right:1px solid color-mix(in srgb,\(style.ink) 20%,transparent);border-bottom:1px solid color-mix(in srgb,\(style.ink) 20%,transparent)}.card.active{color:white;background:\(style.accent)}.card span{font-size:10px;letter-spacing:.12em}.card h2{margin:55px 0 8px;font:500 27px/1 ui-serif,Georgia,serif}.card p{margin:0;font-size:12px;line-height:1.45;opacity:.68}@media(max-width:700px){.hero{grid-template-columns:1fr;margin-top:5vh}.hero h1{font-size:54px}.grid{grid-template-columns:1fr 1fr}.card{min-height:150px}.card h2{margin-top:30px}}
            </style></head><body><main><div class="kicker">\(style.kicker) · \(title.uppercased())</div><section class="hero"><h1>\(style.headline)</h1><p>\(style.summary)</p></section><div class="rule"></div><section class="grid">\(cardMarkup)</section></main></body></html>
            """
        guard
            let encoded = html.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ), let url = URL(string: "data:text/html;charset=utf-8,\(encoded)")
        else {
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    private static func tab(
        _ title: String, _ url: URL, _ symbol: String, _ placement: TabPlacement, _ folderID: UUID? = nil,
        splitGroupID: UUID? = nil
    ) -> TabState.Seed {
        TabState.Seed(
            title: title, url: url, symbol: BrowserIconSymbol.symbol(forEmoji: symbol), iconMode: .emoji,
            placement: placement, folderID: folderID, splitGroupID: splitGroupID)
    }

    private static func archivedTab(
        _ title: String, _ url: URL, _ symbol: String, reason: ArchiveReason, secondsAgo: TimeInterval
    ) -> ArchivedTabState.Seed {
        ArchivedTabState.Seed(
            tab: tab(title, url, symbol, .current), archivedAt: .now.addingTimeInterval(-secondsAgo), reason: reason)
    }
}

// MARK: - Page Style

/// The look and copy of one Space's showcase pages.
struct BrowserShowcasePageStyle: Sendable {
    // MARK: - Static Variables

    static let work = BrowserShowcasePageStyle(
        background: "#f3efe5", ink: "#15233b", accent: "#315f98", warm: "#d6ab4e", kicker: "NORTHSTAR STUDIO",
        headline: "Make space for the work that matters.",
        summary: "A calm command center for launches, decisions, and the people moving them forward.",
        cards: [
            ("Today", "Three decisions, one clear priority"),
            ("Atlas", "Research is ready for review"),
            ("Launch", "Milestone check-in at 2:30"),
            ("Notes", "Seven ideas worth keeping"),
        ])
    static let personal = BrowserShowcasePageStyle(
        background: "#eef2e8", ink: "#20372d", accent: "#6d8d68", warm: "#d7684f", kicker: "FIELD NOTES",
        headline: "A slower Saturday starts here.",
        summary: "Plans for good food, open roads, a little dirt under your nails, and time to read.",
        cards: [
            ("Weekend", "Market, trail, then nowhere to be"),
            ("Trips", "Cabin map and quiet roads"),
            ("Garden", "What to plant before the rain"),
            ("Reading", "Four essays for Sunday morning"),
        ])

    // MARK: - Variables

    let background: String
    let ink: String
    let accent: String
    let warm: String
    let kicker: String
    let headline: String
    let summary: String

    /// Each card's heading and line, in order.
    let cards: [(String, String)]

    // MARK: - Initializers

    private init(
        background: String, ink: String, accent: String, warm: String, kicker: String, headline: String,
        summary: String, cards: [(String, String)]
    ) {
        self.background = background
        self.ink = ink
        self.accent = accent
        self.warm = warm
        self.kicker = kicker
        self.headline = headline
        self.summary = summary
        self.cards = cards
    }
}

extension SessionState.Seed {
    // MARK: - Variables

    /// The session screenshots and the showcase show.
    static let showcase = SessionShowcaseSeed.make()
}
