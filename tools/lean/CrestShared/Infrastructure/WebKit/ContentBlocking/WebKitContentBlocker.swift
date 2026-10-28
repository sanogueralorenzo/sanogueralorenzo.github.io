import Foundation
import Observation
import WebKit

/// One uBOL context per browsing profile, shared only by that profile's pages.
@MainActor @Observable
final class WebKitContentBlocker: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionWindow {
    // MARK: - Types

    private struct StartupMessage: Decodable {
        enum Event: String, Decodable { case ready, error }
        let event: Event
        let message: String?
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    // MARK: - Variables

    let controller: WKWebExtensionController
    let profileID: UUID
    private(set) var isEnabled = false
    private(set) var errorDescription: String?
    @ObservationIgnored private weak var binding: WebKitEngineBinding?
    @ObservationIgnored private let extensionLoader: @MainActor () async throws -> WKWebExtension
    @ObservationIgnored private let privateSpace: Bool
    @ObservationIgnored private var context: WKWebExtensionContext?
    @ObservationIgnored private var operation: Task<Void, Error>?
    @ObservationIgnored private var requested: Bool?
    @ObservationIgnored private var startup: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    // MARK: - Initializers

    init(
        profileID: UUID, dataStore: WKWebsiteDataStore, isPrivate: Bool, binding: WebKitEngineBinding,
        extensionLoader: @escaping @MainActor () async throws -> WKWebExtension
    ) {
        self.profileID = profileID
        self.binding = binding
        self.extensionLoader = extensionLoader
        privateSpace = isPrivate || !dataStore.isPersistent
        let configuration: WKWebExtensionController.Configuration =
            dataStore.identifier.map { .init(identifier: $0) } ?? .nonPersistent()
        configuration.defaultWebsiteDataStore = dataStore
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    // MARK: - Actions - Protection

    func setEnabled(_ value: Bool) async throws {
        if requested != value || operation == nil || errorDescription != nil {
            requested = value
            let previous = operation
            operation = Task { [self] in
                _ = try? await previous?.value
                guard requested == value else { return }
                do {
                    if value {
                        try await load()
                    } else if let context, context.isLoaded {
                        try controller.unload(context)
                    }
                    isEnabled = value
                    errorDescription = nil
                } catch {
                    isEnabled = false
                    errorDescription = error.localizedDescription
                    throw error
                }
            }
        }
        try await operation?.value
    }

    private func load() async throws {
        if context?.isLoaded == true { return }
        if context == nil {
            let webExtension = try await extensionLoader()
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = "com.pauldavis.crest.ubol"
            context.baseURL = URL(string: "webkit-extension://crest-ubol/")!
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
            try await withCheckedThrowingContinuation { continuation in
                startup = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(45)) } catch { return }
                    self?.finishStartup(
                        .failure(
                            Failure(errorDescription: String(localized: "uBlock Origin Lite did not finish starting.")))
                    )
                }
                do { try controller.load(context) } catch { finishStartup(.failure(error)) }
            }
        } catch {
            if context.isLoaded { try? controller.unload(context) }
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

    // MARK: - Actions - Extension host

    func webExtensionController(
        _ controller: WKWebExtensionController, sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard extensionContext === context, applicationIdentifier == "com.pauldavis.crest",
            let data = try? JSONSerialization.data(withJSONObject: message),
            let message = try? JSONDecoder().decode(StartupMessage.self, from: data)
        else {
            replyHandler(nil, Failure(errorDescription: String(localized: "Unknown content blocking message.")))
            return
        }
        switch message.event {
        case .ready: finishStartup(.success(()))
        case .error:
            finishStartup(
                .failure(
                    Failure(
                        errorDescription: message.message ?? String(localized: "uBlock Origin Lite could not start."))))
        }
        replyHandler(true, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, openWindowsFor context: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] { [self] }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        binding?.pages.values.compactMap(\.value).filter { $0.profileID == profileID && !$0.isClosed } ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        binding?.pages.values.compactMap(\.value).first {
            $0.profileID == profileID && !$0.isClosed && $0.webView.window?.isKeyWindow == true
        }
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { privateSpace }
}
