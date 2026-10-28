import Foundation

/// Reads browser session files only; no Chromium runtime or embedding code is retained.
struct BrowserChromiumSession {
    struct Tab {
        var window: Int?
        var order = Int.max
        var selected = 0
        var entries: [Int: (String, String)] = [:]
        var pinned = false
        var group: String?
        var split: String?
    }
    struct Pickle {
        let bytes: [UInt8]
        var position = 4
        let end: Int
        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            end = min(bytes.count, 4 + (Self.integer(bytes, 0) ?? 0))
        }
        static func integer(_ data: [UInt8], _ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            let value = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
            return Int(Int32(bitPattern: value))
        }
        mutating func integer() -> Int? {
            guard position + 4 <= end else { return nil }
            defer { position += 4 }
            return Self.integer(bytes, position)
        }
        mutating func text(utf16: Bool = false, limit: Int = 8192) -> String? {
            guard let count = integer(), count >= 0, count <= limit else { return nil }
            let size = count * (utf16 ? 2 : 1)
            guard position + size <= end else { return nil }
            let data = Data(bytes[position..<position + size])
            position = (position + size + 3) & ~3
            return String(data: data, encoding: utf16 ? .utf16LittleEndian : .utf8)
        }
    }
    static func token(_ bytes: [UInt8], _ offset: Int) -> String? {
        guard offset + 16 <= bytes.count else { return nil }
        return bytes[offset..<offset + 16].map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ data: Data, name: String) throws -> [BrowserSpace] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Pickle.integer(bytes, 4) == 3 else { throw CocoaError(.fileReadUnsupportedScheme) }
        var tabs: [Int: Tab] = [:]
        var closedTabs = Set<Int>()
        var closedWindows = Set<Int>()
        var titles: [Int: String] = [:]
        var selectedTabs: [Int: Int] = [:]
        var groups: [String: String] = [:]
        var position = 8
        var active: Int?
        while position < bytes.count {
            guard position + 3 <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            let size = Int(bytes[position]) | Int(bytes[position + 1]) << 8
            guard size > 0, position + 2 + size <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            var command = Int(bytes[position + 2])
            let payload = Array(bytes[position + 3..<position + 2 + size])
            position += 2 + size
            if name.localizedCaseInsensitiveContains("vivaldi"), command >= 21, command < 252 {
                if command == 21 || command == 22 { continue }
                command -= 2
            }
            let first = Pickle.integer(payload, 0)
            let second = Pickle.integer(payload, 4)
            switch command {
            case 0:
                if let window = first, let tab = second, !closedTabs.contains(tab) {
                    tabs[tab, default: Tab()].window = window
                }
            case 2: if let first, let second { tabs[first, default: Tab()].order = second }
            case 5:
                if let first, let second {
                    tabs[first, default: Tab()].entries = tabs[first, default: Tab()].entries.filter { $0.key < second }
                }
            case 6:
                var pickle = Pickle(payload)
                if let id = pickle.integer(), let index = pickle.integer(), let url = pickle.text(),
                    let title = pickle.text(utf16: true, limit: 4096),
                    !closedTabs.contains(id), BrowserImportReader.address(url) != nil
                {
                    tabs[id, default: Tab()].entries[index] = (url, title)
                }
            case 7: if let first, let second { tabs[first, default: Tab()].selected = second }
            case 8: if let first, let second { selectedTabs[first] = second }
            case 11:
                if let first, let second {
                    tabs[first, default: Tab()].entries = Dictionary(
                        uniqueKeysWithValues: tabs[first, default: Tab()].entries.filter { $0.key >= second }.map {
                            ($0.key - second, $0.value)
                        })
                    tabs[first, default: Tab()].selected = max(0, tabs[first, default: Tab()].selected - second)
                }
            case 12: if let first, payload.count > 4 { tabs[first, default: Tab()].pinned = payload[4] != 0 }
            case 16:
                if let first {
                    tabs[first] = nil
                    closedTabs.insert(first)
                }
            case 17: if let first { closedWindows.insert(first) }
            case 20: active = first
            case 25, 36:
                if let first, payload.count > 24 {
                    let value = payload[24] == 0 ? nil : token(payload, 8)
                    if command == 25 {
                        tabs[first, default: Tab()].group = value
                    } else {
                        tabs[first, default: Tab()].split = value
                    }
                }
            case 27:
                var pickle = Pickle(payload)
                if let id = token(payload, 4) {
                    pickle.position = 20
                    groups[id] = pickle.text(utf16: true, limit: 4096) ?? "Tab Group"
                }
            case 31:
                var pickle = Pickle(payload)
                if let id = pickle.integer(), let title = pickle.text(limit: 4096) { titles[id] = title }
            default: break
            }
            guard tabs.count <= BrowserSpace.maximumTabCount else { throw CocoaError(.fileReadTooLarge) }
        }
        let windows = Set(tabs.values.compactMap(\.window)).subtracting(closedWindows).sorted { a, b in
            a == active ? true : b == active ? false : a < b
        }
        guard windows.count <= 64 else { throw CocoaError(.fileReadTooLarge) }
        return try windows.enumerated().compactMap { ordinal, window in
            var space = BrowserSpace()
            space.name = titles[window] ?? name + " \(ordinal+1)"
            var folderIDs: [String: UUID] = [:]
            var splits: [String: [UUID]] = [:]
            for (_, tab) in tabs.filter({ $0.value.window == window }).sorted(by: { $0.value.order < $1.value.order }) {
                let keys = tab.entries.keys.sorted()
                guard
                    let entry = tab.entries[tab.selected] ?? keys.first(where: { $0 >= tab.selected }).flatMap({
                        tab.entries[$0]
                    }) ?? keys.last.flatMap({ tab.entries[$0] })
                else { continue }
                var parent: UUID?
                if !tab.pinned, let group = tab.group {
                    if folderIDs[group] == nil {
                        var folder = BrowserFolder()
                        folder.title = groups[group] ?? "Tab Group"
                        space.folders.append(folder)
                        folderIDs[group] = folder.id
                    }
                    parent = folderIDs[group]
                }
                let previous = space.tabs.count
                try BrowserImportReader.append(
                    entry.0, title: entry.1, placement: tab.pinned ? .pinned : .current, parent: parent, space: &space)
                if space.tabs.count > previous, let id = space.tabs.last?.id {
                    if let split = tab.split { splits[split, default: []].append(id) }
                    if tab.order == selectedTabs[window] { space.selectedTabID = id }
                }
            }
            for ids in splits.values where (2...4).contains(ids.count) {
                space.splits.append(BrowserSplit(tabIDs: ids))
            }
            return space.tabs.isEmpty ? nil : space
        }
    }
}
