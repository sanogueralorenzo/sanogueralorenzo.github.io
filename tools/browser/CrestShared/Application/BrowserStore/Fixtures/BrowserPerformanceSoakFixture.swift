import Foundation

enum BrowserPerformanceSoakFixture {
    private static let allowedTabCounts = 2...24
    private static let allowedChromeScaleTabCounts = 2...500
    private static let allowedRunIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func makeSeed(
        baseURLString: String?,
        rawTabCount: String?,
        isHeavy: Bool = false,
        runID: String
    ) -> SessionState.Seed? {
        guard let baseURLString,
            let baseURL = URL(string: baseURLString),
            isSafeLoopback(baseURL),
            let rawTabCount,
            let tabCount = Int(rawTabCount),
            (isHeavy ? allowedChromeScaleTabCounts : allowedTabCounts).contains(tabCount),
            isSafeRunID(runID)
        else { return nil }
        if isHeavy {
            return makeHeavySession(
                baseURL: baseURL,
                tabCount: tabCount,
                runID: runID
            )
        }
        let tabs = (1...tabCount).compactMap { tabIndex in
            performanceTab(
                index: tabIndex,
                runID: runID,
                baseURL: baseURL
            )
        }
        guard tabs.count == tabCount, !tabs.isEmpty else { return nil }
        let space = SpaceState.Seed(
            name: "Performance", symbol: "gauge.with.dots.needle.67percent", accent: .teal, tabs: tabs,
            browsingPreferences: soakBrowsing)
        return SessionState.Seed(spaces: [space])
    }

    /// Google, no cleanup and no content blocking, so nothing a soak measures
    /// is swept or blocked away.
    private static let soakBrowsing = BrowsingPreferences.seeded(cleanup: .never, blocking: .off)

    private static func makeHeavySession(
        baseURL: URL,
        tabCount: Int,
        runID: String
    ) -> SessionState.Seed? {
        let palettes = SpaceHouse.all
        let patterns = SpaceBannerPattern.all.shuffled()
        // Each house look, in a banner pattern of its own and a light fade.
        var appearances = palettes.enumerated().map { index, palette in
            var look = palette.look
            look.bannerPattern = patterns[index % patterns.count]
            look.readabilityFade = 0.12
            return (name: palette.name, branding: look)
        }
        // A bright control beside the original palettes exercises both foreground tones.
        var daylight = SpaceBranding.neutral
        daylight.colors = [.sand, .gold, Tincture.winterIce.color]
        daylight.bannerPattern = .chevron
        daylight.readabilityFade = 0
        daylight.textColorMode = .dark
        appearances.insert((name: "Daylight", branding: daylight), at: 0)
        let spaces = (1...appearances.count).compactMap { spaceIndex -> SpaceState.Seed? in
            let appearance = appearances[spaceIndex - 1]
            let folders = (1...8).map { folderIndex in
                FolderState.Seed(title: "Collection \(spaceIndex)-\(folderIndex)")
            }
            let tabs = (1...tabCount).compactMap { tabIndex -> TabState.Seed? in
                let placement: TabPlacement =
                    tabIndex.isMultiple(of: 3)
                    ? .saved
                    : .current
                let folderID =
                    placement == .saved
                    ? folders[(tabIndex / 3 - 1) % folders.count].id
                    : nil
                return performanceTab(
                    index: (spaceIndex - 1) * tabCount + tabIndex,
                    runID: runID,
                    baseURL: baseURL,
                    placement: placement,
                    folderID: folderID
                )
            }
            guard tabs.count == tabCount, tabs.contains(where: { !$0.placement.isDurable })
            else { return nil }
            let history = (1...96).compactMap { historyIndex -> HistoryEntryState? in
                guard
                    let url = performanceURL(
                        index: spaceIndex * 1_000 + historyIndex,
                        runID: runID,
                        baseURL: baseURL
                    )
                else { return nil }
                let firstVisit = Date(
                    timeIntervalSince1970: 1_700_000_000
                        + Double(spaceIndex * 1_000 + historyIndex)
                )
                return HistoryEntryState(
                    url: url,
                    title: "History \(spaceIndex)-\(historyIndex)",
                    firstVisitedAt: firstVisit,
                    lastVisitedAt: firstVisit.addingTimeInterval(300),
                    visitCount: historyIndex % 5 + 1
                )
            }
            return SpaceState.Seed(
                name: appearance.name, symbol: "gauge.with.dots.needle.67percent", accent: .teal,
                branding: appearance.branding, folders: folders, tabs: tabs, history: history,
                browsingPreferences: soakBrowsing)
        }
        guard spaces.count == appearances.count, !spaces.isEmpty else { return nil }
        return SessionState.Seed(spaces: spaces)
    }

    private static func isSafeLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http",
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host() ?? "")
    }

    private static func isSafeRunID(_ runID: String) -> Bool {
        guard (1...64).contains(runID.count) else { return false }
        return runID.unicodeScalars.allSatisfy(allowedRunIDCharacters.contains)
    }

    private static func performanceTab(
        index: Int,
        runID: String,
        baseURL: URL,
        placement: TabPlacement = .current,
        folderID: UUID? = nil
    ) -> TabState.Seed? {
        guard
            let url = performanceURL(
                index: index,
                runID: runID,
                baseURL: baseURL
            )
        else { return nil }
        return TabState.Seed(
            title: "Performance \(index)",
            url: url,
            symbol: "gauge.with.dots.needle.67percent",
            placement: placement,
            folderID: folderID
        )
    }

    private static func performanceURL(
        index: Int,
        runID: String,
        baseURL: URL
    ) -> URL? {
        let fixtureURL = baseURL.appending(path: "performance.html")
        guard
            var components = URLComponents(
                url: fixtureURL,
                resolvingAgainstBaseURL: false
            )
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "run", value: runID),
            URLQueryItem(name: "tab", value: String(index)),
        ]
        if index == 1 {
            components.queryItems?.append(URLQueryItem(name: "mutate", value: "1"))
        }
        if index == 2 {
            components.queryItems?.append(URLQueryItem(name: "video", value: "1"))
        }
        return components.url
    }
}
