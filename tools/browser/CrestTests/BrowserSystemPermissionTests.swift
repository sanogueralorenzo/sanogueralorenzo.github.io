import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSystemPermissionTests: XCTestCase {
    func testPasskeyStatusReadsDoNotBlockTheMainThread() async {
        let core = CrestCore()
        let passkeyAccess = BrowserPasskeyAccessController(core: core)
        let service = BrowserSystemPermissionService(core: core, passkeyAccess: passkeyAccess) {
            XCTAssertFalse(Thread.isMainThread, "Passkey status can wait synchronously for a system process.")
            return .authorized
        }
        let status = await service.status(for: .passkeys, spaceID: nil)
        XCTAssertEqual(status.state, .allowed)
    }

    func testFailedRequestRestoresActionWithoutInventingPermissionDecision() async {
        let service = TestSystemPermissionService()
        service.requestError = NSError(domain: "test", code: 1)
        let controller = BrowserSystemPermissionController(service: service)
        await controller.refresh(spaceID: nil)
        await controller.request(.location, spaceID: nil)
        XCTAssertFalse(controller.working.contains(.location))
        XCTAssertEqual(controller.status(for: .location).state, .notRequested)
        XCTAssertNotNil(controller.errors[.location])
        service.currentState = .allowed
        await controller.refresh(spaceID: nil)
        XCTAssertEqual(controller.status(for: .location).state, .allowed)
        XCTAssertNil(controller.errors[.location])
    }

    func testChangingSpacesRejectsLateFolderStatus() async throws {
        let service = TestSystemPermissionService()
        let firstSpace = UUID()
        let nextSpace = UUID()
        service.delayedSpaceID = firstSpace
        let controller = BrowserSystemPermissionController(service: service)
        let first = Task { await controller.refresh(spaceID: firstSpace) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while service.delayedStatus == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try XCTUnwrap(service.delayedStatus)
        await controller.refresh(spaceID: nextSpace)
        pending.resume(returning: .init(state: .blocked, detail: "Previous private folder"))
        await first.value
        XCTAssertNil(controller.status(for: .files).detail)
        XCTAssertEqual(controller.status(for: .files).state, .notRequested)
    }

    func testFolderValidationChecksWritesWithoutChangingExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-folder-access-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appending(path: "existing.txt")
        try Data("keep".utf8).write(to: existing)
        try BrowserSystemFolderAccess.validateDirectory(root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["existing.txt"])
        XCTAssertEqual(try Data(contentsOf: existing), Data("keep".utf8))
        XCTAssertThrowsError(try BrowserSystemFolderAccess.validateDirectory(existing))
    }

    func testRefreshIsReadOnlyAndAnActionIsValidatedAgainstTheSystem() async {
        let service = TestSystemPermissionService()
        let controller = BrowserSystemPermissionController(service: service)
        await controller.refresh(spaceID: nil)
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertEqual(controller.status(for: .camera).state, .notRequested)
        await controller.request(.camera, spaceID: nil)
        XCTAssertEqual(service.requests, [.camera])
        XCTAssertEqual(
            controller.status(for: .camera).state, .blocked,
            "Returning from a request must not be treated as approval.")
        service.currentState = .allowed
        await controller.refresh(spaceID: nil)
        XCTAssertEqual(controller.status(for: .camera).state, .allowed)
        XCTAssertEqual(service.requests, [.camera])
        service.currentState = .notRequested
        await controller.refresh(spaceID: nil)
        service.currentState = .allowed
        await controller.request(.camera, spaceID: nil)
        XCTAssertEqual(controller.status(for: .camera).state, .allowed)
        XCTAssertEqual(
            service.requests, [.camera], "An approval granted elsewhere must be rechecked before requesting again.")
    }

    func testSettingsOpenFailureIsVisibleAndRestrictedPermissionsAreNotRequested() async {
        let service = TestSystemPermissionService()
        service.currentState = .restricted
        let controller = BrowserSystemPermissionController(service: service)
        await controller.refresh(spaceID: nil)
        await controller.request(.camera, spaceID: nil)
        XCTAssertTrue(service.requests.isEmpty)
        controller.openSettings(for: .camera)
        XCTAssertNotNil(controller.errors[.camera])
    }
}

@MainActor
private final class TestSystemPermissionService: BrowserSystemPermissionServicing {
    var currentState = BrowserSystemPermissionState.notRequested
    var requests: [BrowserSystemPermission] = []
    var requestError: Error?
    var delayedSpaceID: UUID?
    var delayedStatus: CheckedContinuation<BrowserSystemPermissionStatus, Never>?

    func status(for permission: BrowserSystemPermission, spaceID: UUID?) async -> BrowserSystemPermissionStatus {
        if permission == .files, let spaceID, spaceID == delayedSpaceID {
            return await withCheckedContinuation { delayedStatus = $0 }
        }
        return .init(state: currentState)
    }

    func request(_ permission: BrowserSystemPermission, spaceID: UUID?) async throws {
        requests.append(permission)
        if let requestError { throw requestError }
        currentState = .blocked
    }

    func chooseFolder(spaceID: UUID) async throws {}
    func openSettings(for permission: BrowserSystemPermission) -> Bool { false }
}
