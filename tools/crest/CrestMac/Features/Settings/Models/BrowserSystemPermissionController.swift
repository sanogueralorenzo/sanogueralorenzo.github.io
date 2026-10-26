import Foundation
import Observation

@MainActor
protocol BrowserSystemPermissionServicing {
    func status(for permission: BrowserSystemPermission, spaceID: UUID?) async -> BrowserSystemPermissionStatus
    func request(_ permission: BrowserSystemPermission, spaceID: UUID?) async throws
    func chooseFolder(spaceID: UUID) async throws
    func openSettings(for permission: BrowserSystemPermission) -> Bool
}

@Observable @MainActor
final class BrowserSystemPermissionController {
    private(set) var statuses: [BrowserSystemPermission: BrowserSystemPermissionStatus] = [:]
    private(set) var errors: [BrowserSystemPermission: String] = [:]
    private(set) var working: Set<BrowserSystemPermission> = []
    @ObservationIgnored private let service: any BrowserSystemPermissionServicing
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var currentSpaceID: UUID?

    init(service: any BrowserSystemPermissionServicing) {
        self.service = service
    }

    func status(for permission: BrowserSystemPermission) -> BrowserSystemPermissionStatus {
        statuses[permission] ?? .init(state: .checking)
    }

    func refresh(spaceID: UUID?, recheckFiles: Bool = false) async {
        let revision = UUID()
        refreshID = revision
        if currentSpaceID != spaceID {
            statuses[.files] = nil
            errors[.files] = nil
        }
        currentSpaceID = spaceID
        if recheckFiles, spaceID != nil,
            [.allowed, .blocked].contains(status(for: .files).state), !working.contains(.files)
        {
            do { try await service.request(.files, spaceID: spaceID) } catch {
                if revision == refreshID { errors[.files] = error.localizedDescription }
            }
        }
        for permission in BrowserSystemPermission.all {
            let status = await service.status(for: permission, spaceID: spaceID)
            guard revision == refreshID, !Task.isCancelled else { return }
            statuses[permission] = status
            if status.state == .allowed { errors[permission] = nil }
        }
    }

    func request(_ permission: BrowserSystemPermission, spaceID: UUID?) async {
        guard !working.contains(permission) else { return }
        working.insert(permission)
        defer { working.remove(permission) }
        let current = await service.status(for: permission, spaceID: spaceID)
        guard currentSpaceID == spaceID else { return }
        statuses[permission] = current
        guard current.state == .notRequested || permission.checksSpaceFolder else { return }
        errors[permission] = nil
        do { try await service.request(permission, spaceID: spaceID) } catch {
            if currentSpaceID == spaceID { errors[permission] = error.localizedDescription }
        }
        guard currentSpaceID == spaceID else { return }
        await refresh(spaceID: spaceID)
    }

    func chooseFolder(spaceID: UUID) async {
        guard !working.contains(.files) else { return }
        working.insert(.files)
        errors[.files] = nil
        defer { working.remove(.files) }
        do { try await service.chooseFolder(spaceID: spaceID) } catch {
            if currentSpaceID == spaceID { errors[.files] = error.localizedDescription }
        }
        guard currentSpaceID == spaceID else { return }
        await refresh(spaceID: spaceID)
    }

    func openSettings(for permission: BrowserSystemPermission) {
        errors[permission] =
            service.openSettings(for: permission)
            ? nil
            : String(
                localized: "System Settings could not open. Open it from the Apple menu and choose Privacy & Security.")
    }
}
