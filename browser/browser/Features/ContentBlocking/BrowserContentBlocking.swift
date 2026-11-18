import Foundation
import WebKit

/// One uBO Lite instance per Space. Only this Space's pages are exposed to it.
@MainActor
final class BrowserContentBlocking: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionWindow {
    let controller: WKWebExtensionController
    let spaceID: UUID
    private weak var owner: BrowserSessionOwner?
    private let privateSpace: Bool
    private var context: WKWebExtensionContext?
    private var operation: Task<Void, Error>?
    private var enabled: Bool?
    private var startup: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private let cache: BrowserContentRuleCache?
    private var cacheBuild: Task<Void, Never>?
    private var cachedRulesets: [String]?
    private var nativeRules: WKContentRuleList?
    private let contentControllers = NSHashTable<WKUserContentController>.weakObjects()

    private static let rulePermissions: [WKWebExtension.Permission] = [
        .declarativeNetRequest, .declarativeNetRequestWithHostAccess,
    ]
    private static var extensionTask: Task<WKWebExtension, Error>?
    private static var cachedExtensionTask: Task<WKWebExtension, Error>?

    init(spaceID: UUID, owner: BrowserSessionOwner, dataStore: WKWebsiteDataStore) {
        self.spaceID = spaceID
        self.owner = owner
        privateSpace = !dataStore.isPersistent
        cache = dataStore.isPersistent ? BrowserContentRuleCache(spaceID: spaceID, profile: owner.persistence.directory) : nil
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
        if let (rules, rulesets) = await cache?.load() {
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
        let webExtension = try await Self.webExtension(cached: cached)
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

    private static func webExtension(cached: Bool) async throws -> WKWebExtension {
        if let task = cached ? cachedExtensionTask : extensionTask {
            return try await task.value
        }
        let task = Task {
            guard let url = Bundle.main.url(
                forResource: cached ? "uBlockOriginLiteCached" : "uBlockOriginLite",
                withExtension: cached ? nil : "zip")
            else { throw CocoaError(.fileNoSuchFile) }
            return try await WKWebExtension(resourceBaseURL: url)
        }
        if cached { cachedExtensionTask = task } else { extensionTask = task }
        do {
            return try await task.value
        } catch {
            if cached { cachedExtensionTask = nil } else { extensionTask = nil }
            throw error
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

    private func buildCache(snapshot: String?) {
        guard let cache, let snapshot,
            let rulesets = try? JSONDecoder().decode([String].self, from: Data(snapshot.utf8)),
            !rulesets.isEmpty
        else { return }
        let previous = cacheBuild
        previous?.cancel()
        cacheBuild = Task {
            await previous?.value
            do {
                try await Task.sleep(for: .seconds(2))
                try await cache.build(rulesets: rulesets)
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

    func removeData() async {
        try? await setEnabled(false)
        cacheBuild?.cancel()
        await cacheBuild?.value
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
            if startup != nil, cachedRulesets == nil { buildCache(snapshot: message["snapshot"]) }
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
    func prewarmContentBlocking() {
        Task { [weak self] in
            guard let self, !isClosed else { return }
            let spaceID = activeSpace.id
            guard spacePreferences(spaceID).blocksContent else { return }
            try? await contentBlocker(for: spaceID).setEnabled(true)
        }
    }

    func contentBlocker(for spaceID: UUID) -> BrowserContentBlocking {
        if let blocker = owner.contentBlockers[spaceID] { return blocker }
        let blocker = BrowserContentBlocking(spaceID: spaceID, owner: owner, dataStore: profile(for: spaceID))
        owner.contentBlockers[spaceID] = blocker
        return blocker
    }

    func reloadContentBlocking(in spaceID: UUID? = nil) {
        for page in pages.values where spaceID == nil || page.spaceID == spaceID {
            page.applyContentBlocking()
            page.reloadAfterContentBlocking()
        }
    }
}
