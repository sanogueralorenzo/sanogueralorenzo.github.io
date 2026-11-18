import AppKit
import Foundation

@MainActor struct BrowserPaletteResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    var spaceColor: Int? = nil
    var address: URL? = nil
    let score: Double
    let perform: (BrowserStore) -> Void
}

extension BrowserStore {
    func paletteResults(_ input: String) -> [BrowserPaletteResult] {
        let commandOnly = input.hasPrefix(">")
        let query = (commandOnly ? String(input.dropFirst()) : input).trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [BrowserPaletteResult] = []
        let visibleSpaces = session.spaces.filter { $0.isPrivate == activeSpace.isPrivate }
        if !commandOnly {
            for space in visibleSpaces {
                for tab in space.tabs where !tab.isSettings {
                    let title = tab.customTitle ?? tab.title
                    if let score = Self.matchScore(query, in: title + " " + (tab.url?.absoluteString ?? "")) {
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
                if let score = Self.matchScore(query, in: space.name), !query.isEmpty {
                    results.append(
                        .init(
                            id: "space-\(space.id)", title: space.name, subtitle: "Switch Space", symbol: "capsule.fill",
                            spaceColor: space.color,
                            score: score + 10, perform: { $0.selectSpace(space.id) }))
                }
                for folder in space.folders {
                    if let score = Self.matchScore(query, in: folder.title), !query.isEmpty {
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
                if let score = Self.matchScore(query, in: visit.title + " " + visit.url.absoluteString) {
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
            if let score = Self.matchScore(query, in: command.title + " " + command.aliases) {
                results.append(
                    .init(
                        id: "command-" + command.title, title: command.title, subtitle: command.shortcut,
                        symbol: command.symbol,
                        score: score + (commandOnly ? 100 : -30), perform: command.action))
            }
        }
        if !commandOnly, let url = SearchProvider.explicitAddress(query),
            !Self.hasHostCompletion(query, for: url, in: results)
        {
            results.removeAll { BrowserURLs.same($0.address, url) }
            results.append(
                .init(
                    id: "address-\(url.absoluteString)", title: url.absoluteString, subtitle: "Open Address",
                    symbol: "arrow.up.right", address: url, score: 500,
                    perform: { $0.submitAddress(url) }))
        }
        return Array(results.sorted { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }.prefix(10))
    }

    private static func hasHostCompletion(_ query: String, for url: URL, in results: [BrowserPaletteResult]) -> Bool {
        guard let typedHost = url.host()?.lowercased(), query.lowercased() == typedHost else { return false }
        let prefix = typedHost.hasPrefix("www.") ? String(typedHost.dropFirst(4)) : typedHost
        return results.contains { result in
            guard let host = result.address?.host()?.lowercased() else { return false }
            let hostname = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            guard hostname.hasPrefix(prefix), hostname != prefix else { return false }
            return hostname.dropFirst(prefix.count).first != "."
        }
    }

    static func matchScore(_ query: String, in text: String) -> Double? {
        guard !query.isEmpty else { return 0 }
        let query = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if text == query { return 200 }
        if text.hasPrefix(query) { return 150 - Double(text.count - query.count) * 0.05 }
        if let range = text.range(of: query) {
            return 100 - Double(text.distance(from: text.startIndex, to: range.lowerBound)) * 0.3
        }
        var cursor = text.startIndex
        var gap = 0
        for character in query {
            guard let index = text[cursor...].firstIndex(of: character) else { return nil }
            gap += text.distance(from: cursor, to: index)
            cursor = text.index(after: index)
        }
        return max(0, 45 - Double(gap))
    }
}
