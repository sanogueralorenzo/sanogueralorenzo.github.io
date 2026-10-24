import AppKit
import SwiftUI

struct BrowserSystemPermissionSettingsSection: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @Environment(BrowserPasskeyAccessController.self) private var passkeyAccess

    var body: some View {
        BrowserSystemPermissionSettingsContent(
            browser: browser, spaceAccess: spaceAccess,
            service: BrowserSystemPermissionService(core: browser.core, passkeyAccess: passkeyAccess))
    }
}

/// The permission rows over one permission service. The service is made once,
/// when the section first appears.
private struct BrowserSystemPermissionSettingsContent: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @State private var controller: BrowserSystemPermissionController

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, service: BrowserSystemPermissionService) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        _controller = State(initialValue: BrowserSystemPermissionController(service: service))
    }

    private var spaceID: UUID? {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return nil }
        return space.id
    }

    var body: some View {
        Section("System permissions") {
            ForEach(BrowserSystemPermission.all) { permission in
                BrowserSystemPermissionRow(
                    permission: permission,
                    status: controller.status(for: permission),
                    error: controller.errors[permission],
                    isWorking: controller.working.contains(permission),
                    spaceName: spaceID == nil ? nil : browser.shownSpace?.settings.name,
                    request: { Task { await controller.request(permission, spaceID: spaceID) } },
                    openSettings: { controller.openSettings(for: permission) },
                    chooseFolder: {
                        guard let spaceID else { return }
                        Task { await controller.chooseFolder(spaceID: spaceID) }
                    }
                )
            }
        }
        .task(id: spaceID) { await controller.refresh(spaceID: spaceID) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh(spaceID: spaceID, recheckFiles: true) }
        }
    }
}
