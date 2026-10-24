import AVFoundation
import SwiftUI
import UserNotifications

/// A macOS privacy permission the General pane checks and requests for Crest.
/// Each permission carries its row's text, glyph and tint, where System
/// Settings shows it, and how the system API that owns it is read and asked.
struct BrowserSystemPermission: Hashable, Identifiable, Sendable {
    // MARK: - Types

    typealias StatusReader =
        @MainActor @Sendable (BrowserSystemPermissionService, UUID?) async -> BrowserSystemPermissionStatus
    typealias AccessRequest = @MainActor @Sendable (BrowserSystemPermissionService, UUID?) async throws -> Void

    // MARK: - Static Variables

    static let camera = BrowserSystemPermission(
        name: "camera", title: "Camera",
        explanation: "Use your camera on websites for video calls and other features.", symbol: "camera.fill",
        tint: .green, settingsPane: "com.apple.preference.security?Privacy_Camera",
        status: { service, _ in await service.captureStatus(.video) },
        request: { _, _ in _ = await AVCaptureDevice.requestAccess(for: .video) })
    static let microphone = BrowserSystemPermission(
        name: "microphone", title: "Microphone",
        explanation: "Use your microphone on websites for calls and recording.", symbol: "mic.fill", tint: .orange,
        settingsPane: "com.apple.preference.security?Privacy_Microphone",
        status: { service, _ in await service.captureStatus(.audio) },
        request: { _, _ in _ = await AVCaptureDevice.requestAccess(for: .audio) })
    static let location = BrowserSystemPermission(
        name: "location", title: "Location",
        explanation: "Share your location with websites you allow.", symbol: "location.fill", tint: .blue,
        settingsPane: "com.apple.preference.security?Privacy_LocationServices",
        status: { service, _ in await service.locationStatus() },
        request: { service, _ in try await service.requestLocation() })
    static let notifications = BrowserSystemPermission(
        name: "notifications", title: "Notifications",
        explanation: "Show notifications from websites you allow.", symbol: "bell.badge.fill", tint: .red,
        settingsPane:
            "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "com.pauldavis.crest")",
        status: { service, _ in await service.notificationStatus() },
        request: { _, _ in
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        })
    static let passkeys = BrowserSystemPermission(
        name: "passkeys", title: "Passkeys",
        explanation: "Sign in to websites using passkeys saved with your system providers.",
        symbol: "person.badge.key.fill", tint: .purple, settingsPane: "com.apple.preference.security",
        status: { service, _ in await service.passkeyStatus() },
        request: { service, _ in
            service.passkeyAccess.refreshStatus()
            await service.passkeyAccess.requestAccess()
        })
    static let files = BrowserSystemPermission(
        name: "files", title: "Files & Folders", explanation: "Save downloads and open files you select.",
        symbol: "folder.fill", tint: .blue, settingsPane: "com.apple.preference.security?Privacy_FilesAndFolders",
        checksSpaceFolder: true,
        status: { service, spaceID in service.folderAccess.status(spaceID: spaceID) },
        request: { service, spaceID in
            guard let spaceID else { return }
            try await service.folderAccess.check(spaceID: spaceID)
        })

    /// Every permission, in the order the pane lists them.
    static let all: [BrowserSystemPermission] = [camera, microphone, location, notifications, passkeys, files]

    // MARK: - Variables

    /// The spelling the row's accessibility identifier carries.
    let name: String

    let title: LocalizedStringResource
    let explanation: LocalizedStringResource
    let symbol: String
    let tint: Color

    /// Where System Settings shows the permission, after its URL scheme.
    let settingsPane: String

    /// The permission covers the selected Space's download folder rather than
    /// the app, so it is checked per Space and a folder can be chosen for it.
    let checksSpaceFolder: Bool

    /// Reads where the permission stands from its system API, for the selected
    /// Space where it covers one.
    let status: StatusReader

    /// Asks its system API for the permission.
    let request: AccessRequest

    var id: String { name }

    /// The System Settings page for the permission.
    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:\(settingsPane)")
    }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, explanation: LocalizedStringResource,
        symbol: String, tint: Color, settingsPane: String, checksSpaceFolder: Bool = false,
        status: @escaping StatusReader, request: @escaping AccessRequest
    ) {
        self.name = name
        self.title = title
        self.explanation = explanation
        self.symbol = symbol
        self.tint = tint
        self.settingsPane = settingsPane
        self.checksSpaceFolder = checksSpaceFolder
        self.status = status
        self.request = request
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermission, rhs: BrowserSystemPermission) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// Where a permission stands, with the label, glyph and tint its row shows and
/// the button the row offers for it.
struct BrowserSystemPermissionState: Hashable, Sendable {
    // MARK: - Static Variables

    static let checking = BrowserSystemPermissionState(name: "checking", title: "Checking…")
    static let notRequested = BrowserSystemPermissionState(
        name: "notRequested", title: "Not requested",
        primaryAction: { row in
            if row.error != nil {
                Button("Open Settings", action: row.openSettings)
            } else {
                Button("Allow…", action: row.request)
            }
        })
    static let allowed = BrowserSystemPermissionState(
        name: "allowed", title: "Allowed", symbol: "checkmark.circle.fill", tint: .green,
        primaryAction: { row in
            Button(
                row.permission.checksSpaceFolder ? "Check Again" : "Settings…",
                action: row.permission.checksSpaceFolder ? row.request : row.openSettings)
        })
    static let blocked = BrowserSystemPermissionState(
        name: "blocked", title: "Needs attention", symbol: "exclamationmark.circle.fill", tint: .orange,
        primaryAction: { row in Button("Open Settings", action: row.openSettings) })
    static let restricted = BrowserSystemPermissionState(
        name: "restricted", title: "Restricted by macOS", symbol: "exclamationmark.circle.fill", tint: .orange,
        primaryAction: { row in Button("Open Settings", action: row.openSettings) })
    static let unavailable = BrowserSystemPermissionState(name: "unavailable", title: "Unavailable")
    static let notChecked = BrowserSystemPermissionState(
        name: "notChecked", title: "Not checked",
        primaryAction: { row in Button("Check Access", action: row.request) })
    static let chooseEachTime = BrowserSystemPermissionState(name: "chooseEachTime", title: "Ask where to save")

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color

    /// The button a row offers in this state, if any.
    let primaryAction: @MainActor @Sendable (BrowserSystemPermissionRow) -> Button<Text>?

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String = "circle.dashed", tint: Color = .secondary,
        primaryAction: @escaping @MainActor @Sendable (BrowserSystemPermissionRow) -> Button<Text>? = { _ in nil }
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.primaryAction = primaryAction
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermissionState, rhs: BrowserSystemPermissionState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserSystemPermissionStatus: Equatable {
    var state: BrowserSystemPermissionState
    var detail: String? = nil
}
