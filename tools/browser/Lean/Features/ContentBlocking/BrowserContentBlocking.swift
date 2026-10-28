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

    private static var extensionTask: Task<WKWebExtension, Error>?

    init(spaceID: UUID, owner: BrowserSessionOwner, dataStore: WKWebsiteDataStore) {
        self.spaceID = spaceID
        self.owner = owner
        privateSpace = !dataStore.isPersistent
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
                } else if let context, context.isLoaded {
                    try controller.unload(context)
                }
            }
        }
        try await operation?.value
    }

    private func load() async throws {
        if context?.isLoaded == true { return }
        if context == nil {
            if Self.extensionTask == nil {
                Self.extensionTask = Task {
                    guard let url = Bundle.main.url(forResource: "uBlockOriginLite", withExtension: "zip") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return try await WKWebExtension(resourceBaseURL: url)
                }
            }
            let webExtension = try await Self.extensionTask!.value
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = "dev.leanbrowser.ubol"
            context.baseURL = URL(string: "webkit-extension://lean-ubol/")!
            context.hasAccessToPrivateData = privateSpace
            for permission in webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for pattern in webExtension.requestedPermissionMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
            self.context = context
        }
        guard let context else { return }
        do {
            // Loading the background page alone does not await uBOL's asynchronous
            // rule/script registration. The bundled startup handshake does.
            try await withCheckedThrowingContinuation { continuation in
                startup = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(45)) } catch { return }
                    self?.finishStartup(.failure(BlockingError("uBlock Origin Lite did not finish starting.")))
                }
                do {
                    try controller.load(context)
                } catch {
                    finishStartup(.failure(error))
                }
            }
        } catch {
            if context.isLoaded { try? controller.unload(context) }
            enabled = nil
            throw error
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
        guard extensionContext === context, applicationIdentifier == "dev.leanbrowser",
            let message = message as? [String: String]
        else {
            replyHandler(nil, BlockingError("Unknown content blocking message."))
            return
        }
        if message["event"] == "ready" {
            finishStartup(.success(()))
        } else if message["event"] == "error" {
            finishStartup(.failure(BlockingError(message["message"] ?? "uBlock Origin Lite could not start.")))
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
