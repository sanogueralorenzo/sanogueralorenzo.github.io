import CoreFoundation
import Foundation

/// Crest's existing session document. Selection belongs to the device's window records.
enum SessionDocument {
    typealias Object = [String: Any]
    enum Failure: Error { case unreadable }

    static func read(_ data: Data) throws -> SessionState.Seed { try session(json(data)) }
    static func data(_ value: SessionState.Seed) throws -> Data { try bytes(encode(value)) }
    static func checkpoint(_ value: SessionState.Seed) throws -> [String: Data] {
        var core = value
        var parts: [String: Data] = [:]
        for index in core.spaces.indices {
            let space = core.spaces[index]
            parts["history." + space.id.uuidString] = try bytes(space.history.map(encode))
            core.spaces[index].history = []
        }
        parts["core"] = try data(core)
        return parts
    }
    static func restored(_ parts: [String: Data]) throws -> SessionState.Seed? {
        guard let data = parts["core"] else { return nil }
        var value = try read(data)
        for index in value.spaces.indices {
            guard let history = parts["history." + value.spaces[index].id.uuidString] else { throw Failure.unreadable }
            value.spaces[index].history = try items(json(history)).map(historyEntry)
        }
        return value
    }
    static func bytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func json(_ data: Data) throws -> Any {
        let value = try JSONSerialization.jsonObject(with: data)
        func check(_ value: Any, depth: Int) throws {
            guard depth <= 64 else { throw Failure.unreadable }
            if let object = value as? Object {
                for item in object.values { try check(item, depth: depth + 1) }
            } else if let array = value as? [Any] {
                for item in array { try check(item, depth: depth + 1) }
            }
        }
        try check(value, depth: 0)
        return value
    }
    static func object(_ value: Any?) throws -> Object {
        guard let value = value as? Object else { throw Failure.unreadable }
        return value
    }
    static func present(_ value: Any?) -> Any? { value is NSNull ? nil : value }
    static func items(_ value: Any?) throws -> [Any] {
        guard let value = present(value) else { return [] }
        guard let value = value as? [Any] else { throw Failure.unreadable }
        return value
    }
    static func text(_ value: Any?) throws -> String? {
        guard let value = present(value) else { return nil }
        guard let value = value as? String else { throw Failure.unreadable }
        return value
    }
    static func flag(_ value: Any?) throws -> Bool? {
        guard let value = present(value) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw Failure.unreadable
        }
        return number.boolValue
    }
    static func number(_ value: Any?) throws -> Double? {
        guard let value = present(value) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite
        else { throw Failure.unreadable }
        return number.doubleValue
    }
    static func id(_ value: Any?) throws -> UUID {
        let scalar = (value as? Object)?["rawValue"] ?? value
        guard let spelling = try text(scalar), let id = UUID(uuidString: spelling) else { throw Failure.unreadable }
        return id
    }
    static func optionalID(_ value: Any?) throws -> UUID? { try present(value).map(id) }
    static func wrapped(_ value: UUID) -> Object { ["rawValue": value.uuidString] }
    static func date(_ value: Any?) throws -> Date {
        // The prior shared core bounded stored dates to the range its runtime could represent.
        let seconds = try number(value) ?? 0
        return Date(
            timeIntervalSinceReferenceDate: min(
                max(seconds, -62_135_596_800 - 978_307_200), 253_402_300_800 - 978_307_200))
    }
    static func optionalDate(_ value: Any?) throws -> Date? { try present(value).map(date) }
    static func put(_ value: inout Object, _ key: String, _ item: Any?) { if let item { value[key] = item } }

    static func session(_ input: Any) throws -> SessionState.Seed {
        let value = try object(input)
        guard let spaces = value["spaces"] as? [Any] else { throw Failure.unreadable }
        return try SessionState.Seed(
            spaces: spaces.map(space), disposableSeedMarker: optionalID(value["disposableSeedMarker"]),
            spaceDeletions: items(value["spaceDeletions"]).map { input in
                let value = try object(input)
                return try SpaceDeletionState(
                    id: id(value["operationID"]), spaceID: id(value["spaceID"]), profileID: id(value["profileID"]))
            }, appPreferences: (value["appPreferences"] as? Object).map(preferences))
    }
    static func encode(_ session: SessionState.Seed) -> Object {
        var value: Object = ["spaces": session.spaces.map(encode)]
        put(&value, "disposableSeedMarker", session.disposableSeedMarker?.uuidString)
        if !session.spaceDeletions.isEmpty {
            value["spaceDeletions"] = session.spaceDeletions.map {
                ["operationID": $0.id.uuidString, "spaceID": wrapped($0.spaceID), "profileID": $0.profileID.uuidString]
            }
        }
        put(&value, "appPreferences", session.appPreferences.map(encode))
        return value
    }
    static func space(_ input: Any) throws -> SpaceState.Seed {
        let value = try object(input)
        let identity = try id(value["id"])
        let bytes = withUnsafeBytes(of: identity.uuid) { Array($0) }
        // Guid's first stored byte is byte 3 in RFC 4122 order.
        let color =
            try SpaceColor.named(text(value["spaceColor"])) ?? SpaceColor.all[Int(bytes[3]) % SpaceColor.all.count]
        return try SpaceState.Seed(
            id: identity, profileID: id(object(value["profile"])["id"]), name: text(value["name"]) ?? "Space",
            folders: items(value["folders"]).map(folder), tabs: items(value["tabs"]).map(tab),
            archivedTabs: items(value["archivedTabs"]).map(archived),
            history: items(value["history"]).map(historyEntry),
            browsingPreferences: (value["browsingPreferences"] as? Object).map(browsing) ?? .seeded,
            isGitHubFolderDismissed: flag(value["isGitHubFolderDismissed"]) ?? false, color: color)
    }
    static func encode(_ space: SpaceState.Seed) -> Object {
        var value: Object = [
            "id": wrapped(space.id), "profile": ["id": space.profileID.uuidString], "name": space.settings.name,
            "spaceColor": space.settings.resolved.color.name, "folders": space.folders.map(encode),
            "tabs": space.tabs.map(encode), "archivedTabs": space.archivedTabs.map(encode),
            "history": space.history.map(encode), "browsingPreferences": encode(space.settings.browsingPreferences),
        ]
        if space.settings.isGitHubFolderDismissed { value["isGitHubFolderDismissed"] = true }
        return value
    }
    static func tab(_ input: Any) throws -> TabState.Seed {
        let value = try object(input)
        let native = try (value["nativeContent"] as? Object).map { value in
            NativeTabContent(kind: try text(value["kind"]) ?? "", resourceID: try optionalID(value["resourceID"]))
        }
        if let native, BrowserAddress.trimmed(native.kind).isEmpty { throw Failure.unreadable }
        let url = try native == nil ? text(value["url"]) : nil
        let title = try text(value["title"])
        let known = NativeView.named(native?.kind)
        let name =
            native != nil
            ? known?.title.key ?? (title.flatMap { BrowserAddress.trimmed($0).isEmpty ? nil : $0 } ?? "Native Tab")
            : url ?? TabState.Seed.startPageTitle
        let symbol =
            native != nil
            ? known?.symbol ?? "square" : url == nil ? TabState.Seed.startPageSymbol : TabIconMode.webSymbol
        return try TabState.Seed(
            id: id(value["id"]), title: title ?? name, url: url, nativeContent: native,
            savedURL: native == nil ? text(value["savedURL"]) : nil, symbol: text(value["symbol"]) ?? symbol,
            faviconURL: text(value["faviconURL"]), iconAccent: (value["iconAccent"] as? Object).map(accent),
            storedIconMode: TabIconMode.named(text(value["storedIconMode"])),
            placement: TabPlacement.named(text(value["placement"])) ?? .saved, folderID: optionalID(value["folderID"]),
            splitGroupID: optionalID(value["splitGroupID"]), lastActivatedAt: date(value["lastActivatedAt"]),
            positionModifiedAt: optionalDate(value["positionModifiedAt"]), customTitle: text(value["customTitle"]),
            titleModifiedAt: optionalDate(value["titleModifiedAt"]))
    }
    static func encode(_ tab: TabState.Seed) -> Object {
        var value: Object = [
            "id": wrapped(tab.id), "title": tab.title, "symbol": tab.symbol, "placement": tab.placement.name,
            "lastActivatedAt": tab.lastActivatedAt.timeIntervalSinceReferenceDate,
        ]
        put(&value, "url", tab.url)
        put(&value, "savedURL", tab.savedURL)
        if let native = tab.nativeContent {
            var content: Object = ["kind": native.kind]
            put(&content, "resourceID", native.resourceID?.uuidString)
            value["nativeContent"] = content
        }
        put(&value, "faviconURL", tab.faviconURL)
        put(&value, "iconAccent", tab.iconAccent.map(encode))
        put(&value, "storedIconMode", tab.storedIconMode?.name)
        put(&value, "folderID", tab.folderID.map(wrapped))
        put(&value, "splitGroupID", tab.splitGroupID.map(wrapped))
        put(&value, "positionModifiedAt", tab.positionModifiedAt?.timeIntervalSinceReferenceDate)
        put(&value, "customTitle", tab.customTitle)
        put(&value, "titleModifiedAt", tab.titleModifiedAt?.timeIntervalSinceReferenceDate)
        return value
    }
    static func accent(_ value: Object) throws -> TabIconAccent {
        try TabIconAccent(
            red: number(value["red"]) ?? 0, green: number(value["green"]) ?? 0, blue: number(value["blue"]) ?? 0)
    }
    static func encode(_ value: TabIconAccent) -> Object {
        ["red": value.red, "green": value.green, "blue": value.blue]
    }
    static func color(_ value: Object) throws -> BrandColor {
        try BrandColor(
            red: number(value["red"]) ?? 0, green: number(value["green"]) ?? 0, blue: number(value["blue"]) ?? 0,
            alpha: number(value["alpha"]) ?? 1)
    }
    static func encode(_ value: BrandColor) -> Object {
        ["red": value.red, "green": value.green, "blue": value.blue, "alpha": value.alpha]
    }
    static func archived(_ input: Any) throws -> ArchivedTabState.Seed {
        let value = try object(input)
        let origin = try text(value["deletionOrigin"])
        let reason =
            try ArchiveReason.all.first { $0.deletionOrigin != nil && $0.deletionOrigin == origin }
            ?? ArchiveReason.named(text(value["reason"])) ?? .closed
        return try ArchivedTabState.Seed(
            tab: tab(value["tab"] as Any), archivedAt: date(value["archivedAt"]), reason: reason)
    }
    static func encode(_ value: ArchivedTabState.Seed) -> Object {
        var result: Object = [
            "tab": encode(value.tab), "archivedAt": value.archivedAt.timeIntervalSinceReferenceDate,
            "reason": value.reason.storedReason,
        ]
        put(&result, "deletionOrigin", value.reason.deletionOrigin)
        return result
    }
    static func folder(_ input: Any) throws -> FolderState.Seed {
        let value = try object(input)
        let options = try (value["githubOptions"] as? Object).map(liveOptions)
        return try FolderState.Seed(
            id: id(value["id"]), title: text(value["title"]) ?? "Folder",
            location: TabPlacement.named(text(value["location"])) == .current ? .current : .saved,
            color: (value["color"] as? Object).map(color), parentID: optionalID(value["parentID"]),
            isCollapsed: flag(value["isCollapsed"]) ?? false,
            collapseModifiedAt: optionalDate(value["collapseModifiedAt"]),
            orderAnchorTabID: optionalID(value["orderAnchorTabID"]),
            source: LiveFolderSource.named(text(value["liveFolderSource"])),
            liveOptions: options?.isValid == true ? options?.normalized : nil)
    }
    static func encode(_ value: FolderState.Seed) -> Object {
        var result: Object = [
            "id": wrapped(value.id), "location": value.location.name, "title": value.title,
            "isCollapsed": value.isCollapsed,
        ]
        put(&result, "color", value.color.map(encode))
        put(&result, "parentID", value.parentID.map(wrapped))
        put(&result, "collapseModifiedAt", value.collapseModifiedAt?.timeIntervalSinceReferenceDate)
        put(&result, "orderAnchorTabID", value.orderAnchorTabID.map(wrapped))
        put(&result, "liveFolderSource", value.source?.name)
        put(&result, "githubOptions", value.liveOptions.map(encode))
        return result
    }
    static func liveOptions(_ value: Object) throws -> GitHubLiveFolderOptions {
        try GitHubLiveFolderOptions(
            authorMe: flag(value["authorMe"]) ?? false, assignedMe: flag(value["assignedMe"]) ?? true,
            reviewRequested: flag(value["reviewRequested"]) ?? false,
            includeDrafts: flag(value["includeDrafts"]) ?? true,
            excludedRepositories: (value["repoExcludes"] as? [Any])?.map { try text($0) ?? "" } ?? [],
            interval: LiveFolderRefreshInterval.named(text(value["interval"])) ?? .thirtyMinutes)
    }
    static func encode(_ value: GitHubLiveFolderOptions) -> Object {
        [
            "authorMe": value.authorMe, "assignedMe": value.assignedMe, "reviewRequested": value.reviewRequested,
            "includeDrafts": value.includeDrafts, "repoExcludes": value.excludedRepositories,
            "interval": value.interval.name,
        ]
    }
    static func historyEntry(_ input: Any) throws -> HistoryEntryState {
        let value = try object(input)
        guard let url = try text(value["url"]) else { throw Failure.unreadable }
        let count = try number(value["visitCount"]) ?? 1
        guard count == count.rounded(.down), count >= Double(Int32.min), count <= Double(Int32.max) else {
            throw Failure.unreadable
        }
        return try HistoryEntryState(
            id: id(value["id"]), url: url, title: text(value["title"]) ?? "",
            firstVisitedAt: date(value["firstVisitedAt"]), lastVisitedAt: date(value["lastVisitedAt"]),
            visitCount: Int(count))
    }
    static func encode(_ value: HistoryEntryState) -> Object {
        [
            "id": value.id.uuidString, "url": value.url, "title": value.title,
            "firstVisitedAt": value.firstVisitedAt.timeIntervalSinceReferenceDate,
            "lastVisitedAt": value.lastVisitedAt.timeIntervalSinceReferenceDate, "visitCount": value.visitCount,
        ]
    }
    static func browsing(_ value: Object) -> BrowsingPreferences {
        let retention = value["dataRetention"] as? Object ?? [:]
        return BrowsingPreferences(
            contentBlocking: ContentBlockingPolicy.named(value["contentBlockingPolicy"] as? String) ?? .balanced,
            dataRetention: DataRetentionPreferences(
                history: DataRetention.named(retention["history"] as? String) ?? .forever,
                archive: DataRetention.named(retention["archive"] as? String) ?? .forever,
                downloads: DataRetention.named(retention["downloads"] as? String) ?? .forever))
    }
    static func encode(_ value: BrowsingPreferences) -> Object {
        [
            "contentBlockingPolicy": value.contentBlocking.name,
            "dataRetention": [
                "history": value.dataRetention.history.name, "archive": value.dataRetention.archive.name,
                "downloads": value.dataRetention.downloads.name,
            ],
        ]
    }
    static func preferences(_ value: Object) -> AppPreferences {
        var seen: Set<Data> = []
        let languages = (value["excludedTranslationLanguages"] as? [Any] ?? []).compactMap { $0 as? String }.filter {
            language in
            let first =
                BrowserAddress.trimmed(language).components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? ""
            return (2...8).contains(first.utf8.count) && first.utf8.count != 4
                && first.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) }
                && seen.insert(Data(language.utf8)).inserted
        }
        return AppPreferences(
            translationLanguage: (value["translationLanguage"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? AppPreferences.default.translationLanguage,
            searchProvider: SearchProvider.named(value["searchProvider"] as? String) ?? .google,
            translateAutomatically: (try? flag(value["translateAutomatically"])) ?? false,
            excludedTranslationLanguages: languages,
            searchSuggestionsEnabled: (try? flag(value["searchSuggestionsEnabled"])) ?? false)
    }
    static func encode(_ value: AppPreferences) -> Object {
        var result: Object = ["translationLanguage": value.translationLanguage]
        if value.translateAutomatically { result["translateAutomatically"] = true }
        if value.searchSuggestionsEnabled { result["searchSuggestionsEnabled"] = true }
        if !value.excludedTranslationLanguages.isEmpty {
            result["excludedTranslationLanguages"] = value.excludedTranslationLanguages
        }
        if value.searchProvider != .google { result["searchProvider"] = value.searchProvider.name }
        return result
    }
}
