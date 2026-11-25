import Foundation
import WebKit

/// Each uBO Lite instance only sees pages from its Space.
@MainActor
final class BrowserContentBlocking: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionWindow {
    static let preparingLabel = "Getting this Space ready…"

    let controller: WKWebExtensionController
    let spaceID: UUID
    private weak var owner: BrowserSessionOwner?
    private let privateSpace: Bool
    private let isRuleSeed: Bool
    private var context: WKWebExtensionContext?
    private var operation: Task<Void, Error>?
    private var enabled: Bool?
    private var startup: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private let extensionPackage: BrowserContentExtension
    private let cache: BrowserContentRuleCache?
    private var cacheBuild: Task<Void, Never>?
    private var cachedRulesets: [String]?
    private var seedRulesets: [String]?
    private var nativeRules: WKContentRuleList?
    private let contentControllers = NSHashTable<WKUserContentController>.weakObjects()

    private static let rulePermissions: [WKWebExtension.Permission] = [
        .declarativeNetRequest, .declarativeNetRequestWithHostAccess,
    ]
    init(spaceID: UUID, owner: BrowserSessionOwner, dataStore: WKWebsiteDataStore, isRuleSeed: Bool = false) {
        self.spaceID = spaceID
        self.owner = owner
        self.isRuleSeed = isRuleSeed
        privateSpace = !dataStore.isPersistent && !isRuleSeed
        extensionPackage = owner.contentExtension
        cache = dataStore.isPersistent ? owner.contentExtension.package.flatMap {
            BrowserContentRuleCache(profile: owner.persistence.directory, packageHash: $0.manifest.sha256, spaceID: spaceID)
        } : nil
        let configuration: WKWebExtensionController.Configuration =
            privateSpace ? .nonPersistent() : .init(identifier: spaceID)
        configuration.defaultWebsiteDataStore = dataStore
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    func setEnabled(_ value: Bool) async throws {
        if enabled != value || operation == nil {
            enabled = value
            let previous = operation
            operation = Task { [self] in
                _ = try? await previous?.value
                guard enabled == value else { return }
                if value {
                    try await load()
                } else {
                    try unload()
                }
            }
        }
        try await operation?.value
    }

    private func load() async throws {
        if context?.isLoaded == true { return }
        var cached = await cache?.load()
        if cached == nil, !isRuleSeed, !privateSpace, let owner, BrowserContentRuleCache.canUseDefaultRules(in: spaceID) {
            cached = await extensionPackage.prepareDefaultRules(for: owner)
        }
        if let (rules, rulesets) = cached {
            do {
                cachedRulesets = rulesets
                try await loadExtension(cached: true)
                nativeRules = rules
                for content in contentControllers.allObjects {
                    content.add(rules)
                }
                return
            } catch {
                try unload()
            }
        }
        cache?.invalidate()
        do {
            try await loadExtension(cached: false)
        } catch {
            try? unload()
            if enabled == true { enabled = nil }
            throw error
        }
    }

    private func loadExtension(cached: Bool) async throws {
        let webExtension = try await extensionPackage.load(cached ? .cached : .full)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = cached ? BrowserContentRuleCache.extensionID : "com.itsbrowser.ubol"
        context.baseURL = URL(string: BrowserContentRuleCache.extensionURL + "/")!
        context.hasAccessToPrivateData = privateSpace
        for permission in webExtension.requestedPermissions where !Self.rulePermissions.contains(permission) {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.requestedPermissionMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        self.context = context
        for permission in Self.rulePermissions {
            context.setPermissionStatus(.deniedExplicitly, for: permission)
        }
        try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(cached ? 4 : 45)) } catch { return }
                self?.finishStartup(.failure(BlockingError("uBlock Origin Lite did not finish starting.")))
            }
            do {
                try controller.load(context)
            } catch {
                finishStartup(.failure(error))
            }
        }
    }

    private func unload() throws {
        if let nativeRules {
            for content in contentControllers.allObjects {
                content.remove(nativeRules)
            }
        }
        nativeRules = nil
        cachedRulesets = nil
        if let context, context.isLoaded { try controller.unload(context) }
        context = nil
    }

    func register(_ content: WKUserContentController) {
        contentControllers.add(content)
        if let nativeRules { content.add(nativeRules) }
    }

    func buildDefaultRules(in cache: BrowserContentRuleCache) async -> BrowserContentRuleCache.Entry? {
        defer {
            try? unload()
            BrowserContentRuleCache.removeSeed(spaceID)
        }
        do {
            try await setEnabled(true)
            try Task.checkCancellation()
            guard let seedRulesets else { return nil }
            _ = try await extensionPackage.prepareCachedCopy()
            return try await cache.build(rulesets: seedRulesets, from: spaceID)
        } catch {
            return nil
        }
    }

    private func buildCache(rulesets: [String]) {
        guard let cache else { return }
        let previous = cacheBuild
        previous?.cancel()
        cacheBuild = Task { [extensionPackage, spaceID] in
            await previous?.value
            do {
                try await Task.sleep(for: .seconds(2))
                _ = try await extensionPackage.prepareCachedCopy()
                try Task.checkCancellation()
                _ = try await cache.build(rulesets: rulesets, from: spaceID)
            } catch {}
        }
    }

    private func finishStartup(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = startup
        startup = nil
        continuation?.resume(with: result)
    }

    func cancelPreparation() async {
        try? await setEnabled(false)
        cacheBuild?.cancel()
        await cacheBuild?.value
    }

    func removeData() async {
        await cancelPreparation()
        cache?.remove()
        let types = WKWebExtensionController.allExtensionDataTypes
        let records: [WKWebExtension.DataRecord] = await withCheckedContinuation { continuation in
            controller.fetchDataRecords(ofTypes: types) { @Sendable records in
                continuation.resume(returning: records)
            }
        }
        await controller.removeData(ofTypes: types, from: records)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard extensionContext === context, applicationIdentifier == "com.itsbrowser",
            let message = message as? [String: String]
        else {
            replyHandler(nil, BlockingError("Unknown content blocking message."))
            return
        }
        switch message["event"] {
        case "prepare":
            let permissions: [WKWebExtension.Permission] = cachedRulesets == nil ? Self.rulePermissions : [.declarativeNetRequestWithHostAccess]
            for permission in permissions {
                extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            var reply: [String: Any] = ["starting": startup != nil]
            if let cachedRulesets { reply["cachedRulesets"] = cachedRulesets }
            replyHandler(reply, nil)
            return
        case "ready":
            if startup != nil, cachedRulesets == nil,
                let snapshot = message["snapshot"],
                let rulesets = try? JSONDecoder().decode([String].self, from: Data(snapshot.utf8)), !rulesets.isEmpty {
                if isRuleSeed { seedRulesets = rulesets } else { buildCache(rulesets: rulesets) }
            }
            finishStartup(.success(()))
        case "invalidate":
            if startup == nil {
                cacheBuild?.cancel()
                cache?.invalidate()
            }
        case "error":
            finishStartup(.failure(BlockingError(message["message"] ?? "uBlock Origin Lite could not start.")))
        default:
            replyHandler(nil, BlockingError("Unknown content blocking message."))
            return
        }
        replyHandler(true, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, openWindowsFor context: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] { [self] }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        owner?.pages.values.filter { $0.spaceID == spaceID }.map { $0 as any WKWebExtensionTab } ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let owner, let id = owner.activeWindowID, let store = owner.contexts[id],
            store.activeSpace.id == spaceID else { return nil }
        return store.activePage
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { privateSpace }

    private struct BlockingError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

extension BrowserStore {
    func contentBlocker(for spaceID: UUID) -> BrowserContentBlocking {
        owner.contentBlocker(for: spaceID)
    }

    func reloadContentBlocking(in spaceID: UUID? = nil) {
        for page in pages.values where spaceID == nil || page.spaceID == spaceID {
            page.applyContentBlocking()
            page.reloadAfterContentBlocking()
        }
    }
}

extension BrowserSessionOwner {
    func prewarmContentBlocking(in spaceID: UUID) {
        Task { [weak self] in
            guard let self, contentExtension.package != nil,
                let space = session.spaces.first(where: { $0.id == spaceID }),
                space.browsingPreferences?.blocksContent ?? session.preferences.blocksContent
            else { return }
            try? await contentBlocker(for: spaceID).setEnabled(true)
        }
    }

    func contentBlocker(for spaceID: UUID) -> BrowserContentBlocking {
        if let blocker = contentBlockers[spaceID] { return blocker }
        let blocker = BrowserContentBlocking(spaceID: spaceID, owner: self, dataStore: profile(for: spaceID))
        contentBlockers[spaceID] = blocker
        return blocker
    }
}
