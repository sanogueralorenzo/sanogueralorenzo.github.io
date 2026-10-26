import AppKit
import SwiftUI

struct BrowserSystemPermissionSettingsSection: View {
    let browser: BrowserStore
    @Environment(BrowserPasskeyAccessController.self) private var passkeyAccess

    var body: some View {
        BrowserSystemPermissionSettingsContent(
            service: BrowserSystemPermissionService(core: browser.core, passkeyAccess: passkeyAccess))
    }
}

/// The permission rows over one permission service. The service is made once,
/// when the section first appears.
private struct BrowserSystemPermissionSettingsContent: View {
    @State private var controller: BrowserSystemPermissionController

    init(service: BrowserSystemPermissionService) {
        _controller = State(initialValue: BrowserSystemPermissionController(service: service))
    }

    var body: some View {
        Section("System permissions") {
            ForEach(BrowserSystemPermission.all) { permission in
                BrowserSystemPermissionRow(
                    permission: permission,
                    status: controller.status(for: permission),
                    error: controller.errors[permission],
                    isWorking: controller.working.contains(permission),
                    request: { Task { await controller.request(permission) } },
                    openSettings: { controller.openSettings(for: permission) }
                )
            }
        }
        .task { await controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh(recheckFiles: true) }
        }
    }
}
