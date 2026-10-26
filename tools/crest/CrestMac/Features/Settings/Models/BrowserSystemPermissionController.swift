import Foundation
import Observation

@MainActor
protocol BrowserSystemPermissionServicing {
    func status(for permission: BrowserSystemPermission) async -> BrowserSystemPermissionStatus
    func request(_ permission: BrowserSystemPermission) async throws
    func openSettings(for permission: BrowserSystemPermission) -> Bool
}

@Observable @MainActor
final class BrowserSystemPermissionController {
    private(set) var statuses: [BrowserSystemPermission: BrowserSystemPermissionStatus] = [:]
    private(set) var errors: [BrowserSystemPermission: String] = [:]
    private(set) var working: Set<BrowserSystemPermission> = []
    @ObservationIgnored private let service: any BrowserSystemPermissionServicing
    @ObservationIgnored private var refreshID = UUID()

    init(service: any BrowserSystemPermissionServicing) {
        self.service = service
    }

    func status(for permission: BrowserSystemPermission) -> BrowserSystemPermissionStatus {
        statuses[permission] ?? .init(state: .checking)
    }

    func refresh(recheckFiles: Bool = false) async {
        let revision = UUID()
        refreshID = revision
        if recheckFiles,
            [.allowed, .blocked].contains(status(for: .files).state), !working.contains(.files)
        {
            do { try await service.request(.files) } catch {
                if revision == refreshID { errors[.files] = error.localizedDescription }
            }
        }
        for permission in BrowserSystemPermission.all {
            let status = await service.status(for: permission)
            guard revision == refreshID, !Task.isCancelled else { return }
            statuses[permission] = status
            if status.state == .allowed { errors[permission] = nil }
        }
    }

    func request(_ permission: BrowserSystemPermission) async {
        guard !working.contains(permission) else { return }
        working.insert(permission)
        defer { working.remove(permission) }
        let current = await service.status(for: permission)
        statuses[permission] = current
        guard current.state == .notRequested || permission.checksFiles else { return }
        errors[permission] = nil
        do { try await service.request(permission) } catch {
            errors[permission] = error.localizedDescription
        }
        await refresh()
    }

    func openSettings(for permission: BrowserSystemPermission) {
        errors[permission] =
            service.openSettings(for: permission)
            ? nil
            : String(
                localized: "System Settings could not open. Open it from the Apple menu and choose Privacy & Security.")
    }
}
