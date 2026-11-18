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
        let match = Self.folded(query)
        var results: [BrowserPaletteResult] = []
        let visibleSpaces = session.spaces.filter { $0.isPrivate == activeSpace.isPrivate }
        if !commandOnly {
            for space in visibleSpaces {
                for tab in space.tabs where !tab.isSettings {
                    let title = tab.customTitle ?? tab.title
                    if let score = Self.pageMatchScore(match, title: title, address: tab.url) {
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
                if let score = Self.matchScore(match, in: space.name), !query.isEmpty {
                    results.append(
                        .init(
                            id: "space-\(space.id)", title: space.name, subtitle: "Switch Space", symbol: "capsule.fill",
                            spaceColor: space.color,
                            score: score + 10, perform: { $0.selectSpace(space.id) }))
                }
                for folder in space.folders {
                    if let score = Self.matchScore(match, in: folder.title), !query.isEmpty {
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
                if let score = Self.pageMatchScore(match, title: visit.title, address: visit.url) {
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
            if let score = Self.matchScore(match, in: command.title + " " + command.aliases, allowsFuzzy: commandOnly) {
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
        guard query.lowercased() == url.host()?.lowercased(), let prefix = addressHost(url) else { return false }
        return results.contains { result in
            guard let host = addressHost(result.address), host.hasPrefix(prefix), host != prefix else { return false }
            return host.dropFirst(prefix.count).first != "."
        }
    }

    private static func addressHost(_ address: URL?) -> String? {
        guard let host = address?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func pageMatchScore(_ query: String, title: String, address: URL?) -> Double? {
        guard !query.isEmpty else { return 0 }
        if let host = addressHost(address).map(folded) {
            if host == query { return 280 }
            if host.hasPrefix(query) { return 260 }
            if host.split(separator: ".").dropLast().contains(where: { $0.hasPrefix(query) }) { return 250 }
        }
        return [matchScore(query, in: title), address.flatMap { matchScore(query, in: $0.absoluteString) }]
            .compactMap { $0 }.max()
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func matchScore(_ query: String, in text: String, allowsFuzzy: Bool = false) -> Double? {
        guard !query.isEmpty else { return 0 }
        let text = folded(text)
        if text == query { return 200 }
        if text.hasPrefix(query) { return 150 - Double(text.count - query.count) * 0.05 }
        var start = text.startIndex
        while let range = text.range(of: query, range: start..<text.endIndex) {
            let preceding = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            if allowsFuzzy || preceding.map({ !$0.isLetter && !$0.isNumber }) != false {
                return 100 - Double(text.distance(from: text.startIndex, to: range.lowerBound)) * 0.3
            }
            start = text.index(after: range.lowerBound)
        }
        guard allowsFuzzy else { return nil }
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
