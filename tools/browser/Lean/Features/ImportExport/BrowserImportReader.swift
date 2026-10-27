import Compression
import Foundation

/// Local import formats are untrusted. Readers only produce bounded, validated browser records.
struct BrowserImportReader {
    static let maximumBytes = 100 * 1_024 * 1_024
    static func read(_ url: URL) throws -> [BrowserSpace] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return try read(data, name: url.deletingPathExtension().lastPathComponent)
    }

    static func read(_ input: Data, name: String) throws -> [BrowserSpace] {
        let data = try decompressed(input)
        if data.starts(with: Data("SNSS".utf8)) { return try BrowserChromiumSession.read(data, name: name) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let session = try? decoder.decode(BrowserSession.self, from: data) {
            try session.validate()
            return remapped(session.persistent().spaces)
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if root["sidebar"] != nil { return try arc(root) }
            if root["spaces"] != nil && root["tabs"] != nil { return try zen(root) }
            if root["windows"] != nil { return try firefox(root, name: name) }
            if let roots = root["roots"] as? [String: Any] {
                var space = BrowserSpace()
                space.name = name
                for key in ["bookmark_bar", "other", "synced"]
                    + roots.keys.sorted().filter({ !["bookmark_bar", "other", "synced", "trash"].contains($0) })
                {
                    if let value = roots[key] as? [String: Any] {
                        try appendBookmark(value, parent: nil, space: &space, depth: 0)
                    }
                }
                return [space]
            }
        }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            var space = BrowserSpace()
            space.name = name
            if let root = plist as? [String: Any], root["WebBookmarkType"] != nil || root["Children"] != nil {
                try appendBookmark(root, parent: nil, space: &space, depth: 0)
                return [space]
            }
            return try safari(plist, name: name)
        }
        if let text = String(data: data, encoding: .utf8), text.localizedCaseInsensitiveContains("<a ") {
            return try html(text, name: name)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    static func address(_ value: Any?) -> URL? {
        guard let value = value as? String, value.utf8.count <= 8192,
            let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.user == nil, parts.password == nil,
            parts.host?.isEmpty == false
        else { return nil }
        return parts.url
    }

    static func append(
        _ value: Any?, title: String, placement: BrowserTab.Placement, parent: UUID?, space: inout BrowserSpace
    ) throws {
        guard let url = address(value) else { return }
        guard space.tabs.count < 20_000 else { throw CocoaError(.fileReadTooLarge) }
        var tab = BrowserTab()
        tab.title = String((title.isEmpty ? url.host ?? "Tab" : title).prefix(2048))
        tab.url = url
        tab.placement = placement
        tab.savedURL = placement == .current ? nil : url
        tab.folderID = parent
        space.tabs.append(tab)
    }

    private static func appendBookmark(_ node: [String: Any], parent: UUID?, space: inout BrowserSpace, depth: Int)
        throws
    {
        guard depth < 32, space.folders.count < 4096 else { throw CocoaError(.fileReadTooLarge) }
        let title =
            node["name"] as? String ?? node["Title"] as? String
            ?? (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? "Folder"
        if let value = node["url"] ?? node["URLString"] {
            try append(value, title: title, placement: .saved, parent: parent, space: &space)
            return
        }
        guard let children = node["children"] as? [[String: Any]] ?? node["Children"] as? [[String: Any]],
            !children.isEmpty
        else { return }
        var folder = BrowserFolder()
        folder.title = String(title.prefix(256))
        folder.parentID = parent
        space.folders.append(folder)
        for child in children { try appendBookmark(child, parent: folder.id, space: &space, depth: depth + 1) }
    }

    private static func decompressed(_ data: Data) throws -> Data {
        guard data.starts(with: Data([109, 111, 122, 76, 122, 52, 48, 0])) else { return data }
        guard data.count >= 12 else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = [UInt8](data)
        let size = (0..<4).reduce(0) { $0 | Int(bytes[8 + $1]) << ($1 * 8) }
        guard size > 0, size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        var result = Data(count: size)
        let count = result.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                compression_decode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!, size,
                    input.bindMemory(to: UInt8.self).baseAddress!.advanced(by: 12), data.count - 12, nil,
                    COMPRESSION_LZ4_RAW)
            }
        }
        guard count == size else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    private static func firefox(_ root: [String: Any], name: String) throws -> [BrowserSpace] {
        guard let windows = root["windows"] as? [[String: Any]], windows.count <= 64 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try windows.enumerated().map { index, window in
            var space = BrowserSpace()
            space.name = windows.count == 1 ? name : name + " \(index+1)"
            var groups: [String: UUID] = [:]
            for group in window["groups"] as? [[String: Any]] ?? [] {
                guard let key = group["id"] as? String else { continue }
                var folder = BrowserFolder()
                folder.title = group["name"] as? String ?? "Tab Group"
                groups[key] = folder.id
                space.folders.append(folder)
            }
            for tab in window["tabs"] as? [[String: Any]] ?? [] {
                let entries = tab["entries"] as? [[String: Any]] ?? []
                guard !entries.isEmpty else { continue }
                let selected = max(0, min(entries.count - 1, (tab["index"] as? Int ?? 1) - 1))
                let entry = entries[selected]
                let parent = (tab["groupId"] as? String).flatMap { groups[$0] }
                try append(
                    entry["url"], title: entry["title"] as? String ?? "",
                    placement: tab["pinned"] as? Bool == true ? .pinned : .current,
                    parent: parent, space: &space)
            }
            return space
        }
    }

    private static func zen(_ root: [String: Any]) throws -> [BrowserSpace] {
        guard let workspaces = root["spaces"] as? [[String: Any]], workspaces.count <= 64,
            let tabs = root["tabs"] as? [[String: Any]]
        else { throw CocoaError(.fileReadCorruptFile) }
        let folders = root["folders"] as? [[String: Any]] ?? []
        var splitIDs = Set((root["splitViewData"] as? [[String: Any]] ?? []).compactMap { $0["groupId"] as? String })
        for group in root["groups"] as? [[String: Any]] ?? [] where group["splitView"] as? Bool == true {
            if let id = group["id"] as? String { splitIDs.insert(id) }
        }
        for folder in folders where folder["splitViewGroup"] as? Bool == true {
            if let id = folder["id"] as? String { splitIDs.insert(id) }
        }
        return try workspaces.enumerated().map { ordinal, workspace in
            guard let workspaceID = workspace["uuid"] as? String else { throw CocoaError(.fileReadCorruptFile) }
            var space = BrowserSpace()
            space.name = workspace["name"] as? String ?? "Zen \(ordinal+1)"
            let own = folders.filter {
                ($0["workspaceId"] ?? $0["workspaceID"]) as? String == workspaceID
                    && $0["splitViewGroup"] as? Bool != true
            }
            var ids: [String: UUID] = [:]
            for folder in own { if let id = folder["id"] as? String { ids[id] = UUID() } }
            func holder(_ id: String?) -> UUID? {
                var current = id
                var seen = Set<String>()
                while let value = current, seen.insert(value).inserted {
                    if let found = ids[value] { return found }
                    let folder = folders.first { $0["id"] as? String == value }
                    current = (folder?["parentId"] ?? folder?["parentID"]) as? String
                }
                return nil
            }
            for folder in own {
                guard let key = folder["id"] as? String, let id = ids[key] else { continue }
                var value = BrowserFolder()
                value.id = id
                value.title = folder["name"] as? String ?? "Folder"
                value.parentID = holder((folder["parentId"] ?? folder["parentID"]) as? String)
                space.folders.append(value)
            }
            var splits: [String: [UUID]] = [:]
            for tab in tabs
            where tab["zenWorkspace"] as? String == workspaceID
                || (tab["zenWorkspace"] == nil && tab["zenEssential"] as? Bool == true)
            {
                let entries = tab["entries"] as? [[String: Any]] ?? []
                guard !entries.isEmpty else { continue }
                let entry = entries[max(0, min(entries.count - 1, (tab["index"] as? Int ?? 1) - 1))]
                let pinned = tab["zenEssential"] as? Bool == true
                let saved = tab["pinned"] as? Bool == true
                let group = tab["groupId"] as? String
                let previous = space.tabs.count
                try append(
                    entry["url"], title: entry["title"] as? String ?? "",
                    placement: pinned ? .pinned : saved ? .saved : .current,
                    parent: saved && !pinned ? holder(group) : nil, space: &space)
                if space.tabs.count > previous, let group, splitIDs.contains(group) {
                    splits[group, default: []].append(space.tabs.last!.id)
                }
            }
            for ids in splits.values where (2...4).contains(ids.count) {
                space.splits.append(BrowserSplit(tabIDs: ids))
            }
            return space
        }
    }

    private static func safari(_ value: Any, name: String) throws -> [BrowserSpace] {
        let root = value as? [String: Any] ?? [:]
        let windows =
            ["Windows", "SessionWindows", "BrowserWindows", "OrderedWindows"].compactMap {
                root[$0] as? [[String: Any]]
            }.first
            ?? (value as? [[String: Any]]) ?? [root]
        guard windows.count <= 64 else { throw CocoaError(.fileReadTooLarge) }
        return try windows.enumerated().map { ordinal, window in
            var space = BrowserSpace()
            space.name = window["Title"] as? String ?? name + " \(ordinal+1)"
            func collect(_ value: Any, depth: Int) throws {
                guard depth < 32 else { return }
                if let dict = value as? [String: Any] {
                    let nested =
                        ["TabState", "SessionState", "PageState", "URIDictionary"].compactMap {
                            dict[$0] as? [String: Any]
                        }.first ?? [:]
                    if let url = ["URL", "URLString", "TabURL", "CurrentURL", "SessionTabURL", "url"].compactMap({
                        dict[$0] ?? nested[$0]
                    }).first {
                        let title =
                            ["Title", "TabTitle", "PageTitle", "title"].compactMap {
                                (dict[$0] ?? nested[$0]) as? String
                            }.first ?? ""
                        try append(
                            url, title: title,
                            placement: (dict["Pinned"] ?? dict["IsPinned"] ?? dict["pinned"]) as? Bool == true
                                ? .pinned : .current,
                            parent: nil, space: &space)
                        return
                    }
                    for child in dict.values { try collect(child, depth: depth + 1) }
                } else if let list = value as? [Any] {
                    for child in list { try collect(child, depth: depth + 1) }
                }
            }
            try collect(window, depth: 0)
            return space
        }
    }

    private static func arc(_ root: [String: Any]) throws -> [BrowserSpace] {
        guard let sidebar = root["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [[String: Any]]
        else { throw CocoaError(.fileReadCorruptFile) }
        func objects(_ value: Any?) -> [(String, [String: Any])] {
            if let values = value as? [Any] {
                var pending: String?
                var result: [(String, [String: Any])] = []
                for value in values {
                    if let text = value as? String {
                        pending = text
                    } else if let node = value as? [String: Any], let id = node["id"] as? String ?? pending {
                        result.append((id, node))
                        pending = nil
                    }
                }
                return result
            }
            return (value as? [String: Any] ?? [:]).compactMap { key, value in
                (value as? [String: Any]).map { ($0["id"] as? String ?? key, $0) }
            }
        }
        func profileKey(_ value: Any?) -> String {
            let value = value as? [String: Any] ?? [:]
            if value["default"] as? Bool == true { return "default" }
            let custom = (value["custom"] as? [String: Any])?["_0"] as? [String: Any] ?? [:]
            return (custom["machineID"] as? String ?? "") + ":" + (custom["directoryBasename"] as? String ?? "")
        }
        var spaces: [BrowserSpace] = []
        for container in containers {
            var items: [String: [String: Any]] = [:]
            for (id, item) in objects(container["items"]) { items[id] = item }
            var favorites: [String: String] = [:]
            let pairs = container["topAppsContainerIDs"] as? [Any] ?? []
            for i in stride(from: 0, to: max(0, pairs.count - 1), by: 2) {
                if let id = pairs[i + 1] as? String { favorites[profileKey(pairs[i])] = id }
            }
            for (_, value) in objects(container["spaces"]) {
                guard spaces.count < 64 else { throw CocoaError(.fileReadTooLarge) }
                var space = BrowserSpace()
                space.name = value["title"] as? String ?? "Arc"
                var visited = Set<String>()
                var splits: [String: [UUID]] = [:]
                func walk(
                    _ id: String, placement: BrowserTab.Placement, parent: UUID?, depth: Int, split: String? = nil
                ) throws {
                    guard depth < 32, visited.insert(id).inserted, let item = items[id],
                        let data = item["data"] as? [String: Any]
                    else { return }
                    if let tab = data["tab"] as? [String: Any] {
                        let count = space.tabs.count
                        try append(
                            tab["savedURL"], title: tab["savedTitle"] as? String ?? item["title"] as? String ?? "",
                            placement: placement,
                            parent: placement == .saved ? parent : nil, space: &space)
                        if let split, space.tabs.count > count {
                            splits[split, default: []].append(space.tabs.last!.id)
                        }
                        return
                    }
                    var folderID = parent
                    if data["list"] != nil && placement == .saved {
                        var folder = BrowserFolder()
                        folder.title = item["title"] as? String ?? "Folder"
                        folder.parentID = parent
                        space.folders.append(folder)
                        folderID = folder.id
                    }
                    for child in item["childrenIds"] as? [String] ?? [] {
                        try walk(
                            child, placement: placement, parent: folderID, depth: depth + 1,
                            split: data["splitView"] != nil ? id : split)
                    }
                }
                if let favorite = favorites[profileKey(value["profile"])] {
                    try walk(favorite, placement: .pinned, parent: nil, depth: 0)
                }
                var placement = BrowserTab.Placement.current
                for section in value["containerIDs"] as? [String] ?? value["newContainerIDs"] as? [String] ?? [] {
                    if section == "pinned" {
                        placement = .saved
                    } else if section == "unpinned" {
                        placement = .current
                    } else {
                        try walk(section, placement: placement, parent: nil, depth: 0)
                    }
                }
                for ids in splits.values where (2...4).contains(ids.count) {
                    space.splits.append(BrowserSplit(tabIDs: ids))
                }
                spaces.append(space)
            }
        }
        return spaces
    }

    private static func html(_ text: String, name: String) throws -> [BrowserSpace] {
        var space = BrowserSpace()
        space.name = name
        let expression = try NSRegularExpression(
            pattern: #"<(\/?)(DL|H3|A)\b([^>]*)>([^<]*)"#, options: [.caseInsensitive])
        let source = text as NSString
        var stack: [UUID?] = [nil]
        var pending: String?
        func decode(_ text: String) -> String {
            guard let data = ("<p>" + text + "</p>").data(using: .utf8),
                let document = try? XMLDocument(data: data, options: .documentTidyHTML),
                let node = try? document.nodes(forXPath: "//p").first
            else { return text }
            return node.stringValue ?? text
        }
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let closing = source.substring(with: match.range(at: 1)) == "/"
            let tag = source.substring(with: match.range(at: 2)).uppercased()
            if tag == "H3" && !closing {
                pending = decode(source.substring(with: match.range(at: 4)))
            } else if tag == "DL" && closing {
                if stack.count > 1 { stack.removeLast() }
            } else if tag == "DL" {
                if let title = pending {
                    guard stack.count < 32, space.folders.count < 4096 else { throw CocoaError(.fileReadTooLarge) }
                    var folder = BrowserFolder()
                    folder.title = title
                    folder.parentID = stack.last ?? nil
                    space.folders.append(folder)
                    stack.append(folder.id)
                    pending = nil
                } else {
                    stack.append(stack.last ?? nil)
                }
            } else if tag == "A" && !closing {
                let attributes = source.substring(with: match.range(at: 3)) as NSString
                let href = try NSRegularExpression(
                    pattern: #"href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, options: .caseInsensitive)
                if let found = href.firstMatch(
                    in: attributes as String, range: NSRange(location: 0, length: attributes.length)),
                    let range = (1...3).map({ found.range(at: $0) }).first(where: { $0.location != NSNotFound })
                {
                    try append(
                        decode(attributes.substring(with: range)),
                        title: decode(source.substring(with: match.range(at: 4))), placement: .saved,
                        parent: stack.last ?? nil, space: &space)
                }
            }
        }
        return [space]
    }

    static func remapped(_ spaces: [BrowserSpace]) -> [BrowserSpace] {
        spaces.map { original in
            var value = original
            value.id = UUID()
            value.isPrivate = false
            value.permissions = []
            value.downloadDirectory = nil
            var ids: [UUID: UUID] = [:]
            for tab in value.tabs { ids[tab.id] = UUID() }
            for folder in value.folders { ids[folder.id] = UUID() }
            value.tabs = value.tabs.map { tab in
                var tab = tab
                tab.id = ids[tab.id]!
                tab.folderID = tab.folderID.flatMap { ids[$0] }
                tab.interactionState = nil
                tab.documentState = nil
                return tab
            }
            value.folders = value.folders.map { folder in
                var folder = folder
                folder.id = ids[folder.id]!
                folder.parentID = folder.parentID.flatMap { ids[$0] }
                return folder
            }
            value.splits = value.splits.map { split in
                var split = split
                split.id = UUID()
                split.tabIDs = split.tabIDs.compactMap { ids[$0] }
                return split
            }
            value.selectedTabID = value.selectedTabID.flatMap { ids[$0] }
            return value
        }
    }
}
