import AVFoundation
import CoreLocation
import SwiftUI
import UserNotifications

struct BrowserSystemSettings: View {
    let store: BrowserStore
    let openSpace: (UUID) -> Void
    @State private var revision = 0
    @State private var notifications = "Not requested"
    @State private var filesStatus = "Not checked"

    var body: some View {
        BrowserSettingsForm {
            Section("System permissions") {
                mediaAccess("Camera", media: .video, pane: "Privacy_Camera")
                mediaAccess("Microphone", media: .audio, pane: "Privacy_Microphone")
                LabeledContent("Location") {
                    HStack {
                        Text(locationStatus).foregroundStyle(.secondary)
                        Button("Open Settings") {
                            BrowserSystemAccess.settings("com.apple.preference.security?Privacy_LocationServices")
                        }
                    }
                }
                LabeledContent("Notifications") {
                    HStack {
                        Text(notifications).foregroundStyle(.secondary)
                        Button(notifications == "Not requested" ? "Allow…" : "Open Settings") {
                            if notifications == "Not requested" {
                                Task {
                                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
                                        .alert, .sound, .badge,
                                    ])
                                    await refreshNotifications()
                                }
                            } else {
                                BrowserSystemAccess.settings("com.apple.Notifications-Settings.extension")
                            }
                        }
                    }
                }
                LabeledContent("Passkeys") {
                    HStack {
                        Text(BrowserSystemAccess.passkeyCapability ? BrowserSystemAccess.passkeyState : "Unavailable")
                            .foregroundStyle(.secondary)
                        if BrowserSystemAccess.passkeyCapability {
                            Button("Allow…") {
                                Task {
                                    await BrowserSystemAccess.requestPasskeys()
                                    revision += 1
                                }
                            }
                        }
                    }
                }
                LabeledContent("Files & Folders") {
                    HStack {
                        Text(filesStatus).foregroundStyle(.secondary)
                        Button("Check Access") {
                            do {
                                let directory = try FileManager.default.url(
                                    for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                                let probe = directory.appendingPathComponent(".lean-access-\(UUID().uuidString)")
                                try Data().write(to: probe, options: .withoutOverwriting)
                                try FileManager.default.removeItem(at: probe)
                                filesStatus = "Allowed"
                            } catch {
                                filesStatus = "Needs attention"
                                store.showNotice(error.localizedDescription)
                            }
                        }
                    }
                }
                Button("Screen Recording Settings") {
                    BrowserSystemAccess.settings("com.apple.preference.security?Privacy_ScreenCapture")
                }
            }.id(revision)
            Section {
                ForEach(store.session.spaces) { space in
                    Button {
                        openSpace(space.id)
                    } label: {
                        HStack {
                            BrowserSpacePill(color: space.color).frame(height: 18)
                            Text(space.name)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            } header: {
                Text("Spaces")
            } footer: {
                Text("Each Space keeps its own history, site permissions and blocking.")
            }
        }
        .task { await refreshNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            revision += 1
            Task { await refreshNotifications() }
        }
    }

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways: "Allowed"
        case .denied, .restricted: "Needs attention"
        case .notDetermined: "Not requested"
        @unknown default: "Unavailable"
        }
    }

    private func mediaAccess(_ title: String, media: AVMediaType, pane: String) -> some View {
        let status = AVCaptureDevice.authorizationStatus(for: media)
        return LabeledContent(title) {
            HStack {
                Text(status == .authorized ? "Allowed" : status == .notDetermined ? "Not requested" : "Needs attention")
                    .foregroundStyle(.secondary)
                Button(status == .notDetermined ? "Allow…" : "Open Settings") {
                    if status == .notDetermined {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: media)
                            revision += 1
                        }
                    } else {
                        BrowserSystemAccess.settings("com.apple.preference.security?" + pane)
                    }
                }
            }
        }
    }

    private func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications =
            settings.authorizationStatus == .notDetermined
            ? "Not requested" : settings.authorizationStatus == .denied ? "Needs attention" : "Allowed"
    }
}
