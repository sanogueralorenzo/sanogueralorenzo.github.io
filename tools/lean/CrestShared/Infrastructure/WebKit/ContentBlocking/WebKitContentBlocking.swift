import Foundation
import Observation
import WebKit

/// Shares the bundled extension while keeping its profile runtimes isolated.
@MainActor @Observable
final class WebKitContentBlocking {
    // MARK: - Variables

    private var blockers: [UUID: WebKitContentBlocker] = [:]
    private var preparationError: String?
    @ObservationIgnored private let resourceURL: URL?
    @ObservationIgnored private var extensionTask: Task<WKWebExtension, Error>?
    var errorDescription: String? { preparationError ?? blockers.values.compactMap(\.errorDescription).first }

    // MARK: - Initializers

    init(
        resourceURL: URL? = Bundle(for: WebKitContentBlocker.self).url(
            forResource: "uBlockOriginLite", withExtension: "zip")
    ) {
        self.resourceURL = resourceURL
    }

    // MARK: - Actions - Preparation

    func prepare() async {
        do {
            _ = try await loadExtension()
            preparationError = nil
        } catch { preparationError = error.localizedDescription }
    }

    private func loadExtension() async throws -> WKWebExtension {
        if extensionTask == nil {
            let resourceURL = resourceURL
            extensionTask = Task {
                guard let resourceURL else { throw CocoaError(.fileNoSuchFile) }
                return try await WKWebExtension(resourceBaseURL: resourceURL)
            }
        }
        do {
            guard let extensionTask else { throw CocoaError(.fileNoSuchFile) }
            return try await extensionTask.value
        } catch {
            extensionTask = nil
            throw error
        }
    }

    // MARK: - Actions - Profiles

    func blocker(
        profileID: UUID, dataStore: WKWebsiteDataStore, isPrivate: Bool, binding: WebKitEngineBinding
    ) -> WebKitContentBlocker {
        if let blocker = blockers[profileID] { return blocker }
        let blocker = WebKitContentBlocker(
            profileID: profileID, dataStore: dataStore, isPrivate: isPrivate, binding: binding,
            extensionLoader: { [weak self] in
                guard let self else { throw CocoaError(.userCancelled) }
                return try await self.loadExtension()
            })
        blockers[profileID] = blocker
        return blocker
    }

    func removeData(profileID: UUID, isEphemeral: Bool) async throws {
        let blocker = blockers[profileID]
        try await blocker?.setEnabled(false)
        let controller: WKWebExtensionController?
        if let blocker {
            controller = blocker.controller
        } else if !isEphemeral {
            let identifier = BrowserLaunchEnvironment.current.websiteDataStoreIdentifier(forProfileID: profileID)
            controller = WKWebExtensionController(configuration: .init(identifier: identifier))
        } else {
            controller = nil
        }
        if let controller {
            let types = WKWebExtensionController.allExtensionDataTypes
            let records: [WKWebExtension.DataRecord] = await withCheckedContinuation { continuation in
                controller.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
            }
            await controller.removeData(ofTypes: types, from: records)
        }
        blockers[profileID] = nil
    }
}
