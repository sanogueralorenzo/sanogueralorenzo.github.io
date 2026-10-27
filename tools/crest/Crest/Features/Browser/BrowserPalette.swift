import AppKit
import Foundation

@MainActor struct BrowserPaletteResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let score: Double
    let perform: (BrowserStore) -> Void
}

@MainActor struct BrowserPaletteCommand {
    let title: String
    let aliases: String
    let symbol: String
    let shortcut: String
    let action: (BrowserStore) -> Void
    static let all: [BrowserPaletteCommand] = [
        .init(
            title: "New Tab", aliases: "create open", symbol: "plus", shortcut: "⌘T",
            action: { $0.presentAddress(newTab: true) }),
        .init(
            title: "New Window", aliases: "window", symbol: "macwindow.badge.plus", shortcut: "⌘N",
            action: { $0.owner.openWindow?(nil) }),
        .init(
            title: "Settings", aliases: "preferences options", symbol: "gearshape", shortcut: "⌘,",
            action: { $0.openSettings() }),
        .init(
            title: "History", aliases: "visited", symbol: "clock.arrow.circlepath", shortcut: "⌘Y",
            action: { $0.utility = .history }),
        .init(
            title: "Archive", aliases: "closed recover restore", symbol: "archivebox", shortcut: "",
            action: { $0.utility = .archive }),
        .init(
            title: "Downloads", aliases: "files resume", symbol: "arrow.down.circle", shortcut: "⇧⌘J",
            action: { $0.utility = .downloads }),
        .init(
            title: "Reader Mode", aliases: "reading article", symbol: "doc.text", shortcut: "",
            action: { $0.activePage?.toggleReader() }),
        .init(
            title: "Translate Page", aliases: "translation language", symbol: "translate", shortcut: "⇧⌘L",
            action: { $0.activePage?.translationRequest &+= 1 }),
        .init(
            title: "Split with New Tab", aliases: "side by side", symbol: "rectangle.split.2x1", shortcut: "",
            action: { $0.beginSplit() }),
        .init(
            title: "Change Split Direction", aliases: "horizontal vertical", symbol: "rectangle.split.1x2",
            shortcut: "", action: { $0.changeSplitDirection() }),
        .init(
            title: "Leave Split View", aliases: "unsplit separate", symbol: "rectangle", shortcut: "",
            action: { $0.leaveSplit() }),
        .init(
            title: "Archive Current Tabs", aliases: "clear cleanup", symbol: "archivebox", shortcut: "",
            action: { $0.clearCurrentTabs() }),
        .init(
            title: "New Private Space", aliases: "incognito", symbol: "eye.slash", shortcut: "",
            action: { $0.savePrivateSpace() }),
        .init(
            title: "Import Browser Data", aliases: "bookmarks safari chrome zen arc firefox",
            symbol: "square.and.arrow.down", shortcut: "", action: { $0.importBrowserData() }),
        .init(
            title: "Export Browser Data", aliases: "backup bookmarks", symbol: "square.and.arrow.up", shortcut: "",
            action: { $0.exportBrowserData() }),
        .init(
            title: "Developer Tools", aliases: "inspect debugger console", symbol: "curlybraces", shortcut: "⌥⌘I",
            action: { $0.activePage?.showDeveloperTools() }),
        .init(
            title: "Reload", aliases: "refresh", symbol: "arrow.clockwise", shortcut: "⌘R",
            action: { $0.activePage?.webView.reload() }),
    ]
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
                                symbol: "rectangle.on.rectangle",
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
                            id: "space-\(space.id)", title: space.name, subtitle: "Switch Space", symbol: "circle.fill",
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
                            symbol: "clock",
                            score: score + min(10, Double(visit.count)) + max(0, 10 - age),
                            perform: { $0.submitAddress(visit.url.absoluteString) }))
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
        return Array(results.sorted { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }.prefix(10))
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

struct BrowserCalculation {
    private var input: [Character]
    private var position = 0
    static func value(_ text: String) -> String? {
        guard text.count <= 200, text.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^()").inverted) != nil,
            text.contains(where: { "+-*/%^".contains($0) }),
            text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.+-*/%^() ").contains($0) })
        else { return nil }
        var parser = BrowserCalculation(input: Array(text.filter { !$0.isWhitespace }))
        guard let value = parser.expression(depth: 0), parser.position == parser.input.count, value.isFinite else {
            return nil
        }
        return value.formatted(.number.precision(.significantDigits(1...12)))
    }
    private mutating func expression(depth: Int) -> Double? {
        guard depth < 32, var value = term(depth: depth + 1) else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            position += 1
            guard let other = term(depth: depth + 1) else { return nil }
            value = op == "+" ? value + other : value - other
        }
        return value
    }
    private mutating func term(depth: Int) -> Double? {
        guard var value = factor(depth: depth + 1) else { return nil }
        while let op = peek(), op == "*" || op == "/" || op == "%" {
            position += 1
            guard let other = factor(depth: depth + 1), op == "*" || other != 0 else { return nil }
            value = op == "*" ? value * other : op == "/" ? value / other : value.truncatingRemainder(dividingBy: other)
        }
        return value
    }
    private mutating func factor(depth: Int) -> Double? {
        guard depth < 32 else { return nil }
        if peek() == "-" {
            position += 1
            return factor(depth: depth + 1).map(-)
        }
        if peek() == "+" {
            position += 1
            return factor(depth: depth + 1)
        }
        var value: Double
        if peek() == "(" {
            position += 1
            guard let number = expression(depth: depth + 1), peek() == ")" else { return nil }
            position += 1
            value = number
        } else {
            let start = position
            while let c = peek(), c.isNumber || c == "." { position += 1 }
            guard start < position, let number = Double(String(input[start..<position])) else { return nil }
            value = number
        }
        if peek() == "^" {
            position += 1
            guard let exponent = factor(depth: depth + 1) else { return nil }
            value = pow(value, exponent)
        }
        return value.isFinite ? value : nil
    }
    private func peek() -> Character? { input.indices.contains(position) ? input[position] : nil }
}
