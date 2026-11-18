import AppKit
import Foundation

@MainActor struct BrowserPaletteResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    var spaceColor: Int? = nil
    var address: URL? = nil
    var isWebSearch = false
    let score: Double
    let perform: (BrowserStore) -> Void
}

extension BrowserStore {
    func paletteResults(_ input: String) -> [BrowserPaletteResult] {
        let commandOnly = input.hasPrefix(">")
        let query = (commandOnly ? String(input.dropFirst()) : input).trimmingCharacters(in: .whitespacesAndNewlines)
        let match = BrowserAddressMatch.folded(query)
        var results: [BrowserPaletteResult] = []
        let visibleSpaces = session.spaces.filter { $0.isPrivate == activeSpace.isPrivate }
        if !commandOnly {
            for space in visibleSpaces {
                for tab in space.tabs where !tab.isSettings {
                    let title = tab.customTitle ?? tab.title
                    if let score = BrowserAddressMatch.pageScore(match, title: title, address: tab.url) {
                        let bonus = tab.placement == .current ? 20.0 : 35.0
                        results.append(
                            .init(
                                id: "tab-\(tab.id)", title: title, subtitle: "\(space.name) · Switch to Tab",
                                symbol: "rectangle.on.rectangle", address: tab.url,
                                score: score + bonus + (space.id == activeSpace.id ? 8 : 0),
                                perform: { store in
                                    if let source = store.pendingSplitSourceID {
                                        store.split(source, with: tab.id)
                                    } else {
                                        store.selectTab(tab.id)
                                    }
                                }))
                    }
                }
                if let score = BrowserAddressMatch.textScore(match, in: space.name), !query.isEmpty {
                    results.append(
                        .init(
                            id: "space-\(space.id)", title: space.name, subtitle: "Switch Space", symbol: "capsule.fill",
                            spaceColor: space.color,
                            score: score + 10, perform: { $0.selectSpace(space.id) }))
                }
                for folder in space.folders {
                    if let score = BrowserAddressMatch.textScore(match, in: folder.title), !query.isEmpty {
                        results.append(
                            .init(
                                id: "folder-\(folder.id)", title: folder.title, subtitle: space.name + " · Folder",
                                symbol: "folder", score: score,
                                perform: { store in
                                    store.selectSpace(space.id)
                                    store.updateFolder(folder.id) { $0.isExpanded = true }
                                }))
                    }
                }
            }
            for visit in session.history where visit.spaceID == activeSpace.id {
                if let score = BrowserAddressMatch.pageScore(match, title: visit.title, address: visit.url) {
                    let age = max(0, Date().timeIntervalSince(visit.date) / 86400)
                    results.append(
                        .init(
                            id: "history-\(visit.id)", title: visit.title, subtitle: visit.url.absoluteString,
                            symbol: "clock", address: visit.url,
                            score: score + min(10, Double(visit.count)) + max(0, 10 - age),
                            perform: { $0.submitAddress(visit.url) }))
                }
            }
            if let number = BrowserCalculation.value(query) {
                results.append(
                    .init(
                        id: "calculation", title: number, subtitle: "Copy Result", symbol: "equal", score: 1000,
                        perform: { _ in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(number, forType: .string)
                        }))
            }
        }
        for command in BrowserPaletteCommand.all {
            if let score = BrowserAddressMatch.textScore(match, in: command.title + " " + command.aliases, allowsFuzzy: commandOnly) {
                results.append(
                    .init(
                        id: "command-" + command.title, title: command.title, subtitle: command.shortcut,
                        symbol: command.symbol,
                        score: score + (commandOnly ? 100 : -30), perform: command.action))
            }
        }
        let explicitAddress = commandOnly ? nil : SearchProvider.explicitAddress(query)
        if let url = explicitAddress, !Self.hasHostCompletion(query, for: url, in: results) {
            results.removeAll { BrowserURLs.same($0.address, url) }
            results.append(
                .init(
                    id: "address-\(url.absoluteString)", title: url.absoluteString, subtitle: "Open Address",
                    symbol: "arrow.up.right", address: url, score: 500,
                    perform: { $0.submitAddress(url) }))
        }
        results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        if !commandOnly, explicitAddress == nil, (1...8).contains(query.count),
            !query.contains(where: \.isWhitespace),
            results.first.map({ $0.address != nil && BrowserAddressMatch.hostScore(match, address: $0.address) == nil }) ?? true,
            let url = preferences.searchProvider.searchURL(query)
        {
            results.insert(
                .init(
                    id: "web-search", title: query, subtitle: preferences.searchProvider.rawValue,
                    symbol: "magnifyingglass", isWebSearch: true, score: (results.first?.score ?? 0) + 1,
                    perform: { $0.submitAddress(url) }),
                at: 0)
        }
        return Array(results.prefix(10))
    }

    private static func hasHostCompletion(_ query: String, for url: URL, in results: [BrowserPaletteResult]) -> Bool {
        guard query.lowercased() == url.host()?.lowercased(), let prefix = BrowserAddressMatch.hostName(url) else { return false }
        return results.contains { result in
            guard let host = BrowserAddressMatch.hostName(result.address), host.hasPrefix(prefix), host != prefix else { return false }
            return host.dropFirst(prefix.count).first != "."
        }
    }
}
