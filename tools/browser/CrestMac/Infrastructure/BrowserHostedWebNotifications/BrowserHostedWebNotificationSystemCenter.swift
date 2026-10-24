import AppKit
import Foundation
import UserNotifications

/// Delivers web notifications through macOS while Crest runs. The owner
/// controls their lifetime: a document for WebKit, a document or profile for
/// Chromium. This service does not provide background wake-up or Web Push.
@MainActor
final class BrowserHostedWebNotificationSystemCenter:
    BrowserHostedWebNotificationCentering
{
    nonisolated static let systemIdentifierPrefix = "crest.hosted-page.notification."

    private let center: UNUserNotificationCenter
    private let responder = BrowserHostedWebNotificationSystemResponder.shared
    private var eventHandlers: [String: @MainActor (BrowserHostedWebNotificationEvent) -> Void] = [:]
    private var terminationObserver: NSObjectProtocol?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        responder.hostedPageOwner = self
        center.delegate = responder
        removeOrphanedNotifications()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeActiveNotifications()
            }
        }
    }

    func currentAuthorization() async -> BrowserSystemAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(
                    returning: Self.authorization(from: settings)
                )
            }
        }
    }

    func requestAuthorization() async -> BrowserSystemAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return await currentAuthorization()
        }
    }

    func add(
        _ delivery: BrowserHostedWebNotificationDelivery,
        eventHandler: @escaping @MainActor (BrowserHostedWebNotificationEvent) -> Void
    ) async throws {
        let systemIdentifier = Self.systemIdentifier(for: delivery.identifier)
        let content = UNMutableNotificationContent()
        content.title = delivery.title
        content.subtitle = delivery.origin.host
        content.body = delivery.body
        content.threadIdentifier = "\(Self.systemIdentifierPrefix)thread.\(delivery.origin.host)"
        if !delivery.isSilent {
            content.sound = .default
        }
        eventHandlers[systemIdentifier] = eventHandler
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: systemIdentifier,
                    content: content,
                    trigger: nil
                )
            )
        } catch {
            eventHandlers.removeValue(forKey: systemIdentifier)
            throw error
        }
    }

    func remove(identifier: String) async {
        let systemIdentifier = Self.systemIdentifier(for: identifier)
        eventHandlers.removeValue(forKey: systemIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: [systemIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [systemIdentifier])
    }

    func receive(systemIdentifier: String, actionIdentifier: String) {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
            let eventHandler = eventHandlers.removeValue(forKey: systemIdentifier)
        else { return }
        eventHandler(.clicked)
    }

    private static func systemIdentifier(for identifier: String) -> String {
        "\(systemIdentifierPrefix)\(identifier)"
    }

    private func removeActiveNotifications() {
        let identifiers = Array(eventHandlers.keys)
        eventHandlers.removeAll()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func removeOrphanedNotifications() {
        let centerReference = BrowserUncheckedSendableNotificationCenter(center)
        center.getPendingNotificationRequests { [centerReference] requests in
            let identifiers = requests.map(\.identifier).filter {
                $0.hasPrefix(Self.systemIdentifierPrefix)
            }
            centerReference.value.removePendingNotificationRequests(
                withIdentifiers: identifiers
            )
        }
        center.getDeliveredNotifications { [centerReference] notifications in
            let identifiers = notifications.map(\.request.identifier).filter {
                $0.hasPrefix(Self.systemIdentifierPrefix)
            }
            centerReference.value.removeDeliveredNotifications(
                withIdentifiers: identifiers
            )
        }
    }

    nonisolated private static func authorization(
        from settings: UNNotificationSettings
    ) -> BrowserSystemAuthorization {
        switch settings.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            if settings.alertSetting == .enabled
                || settings.notificationCenterSetting == .enabled
                || settings.lockScreenSetting == .enabled
            {
                .authorized
            } else {
                .denied
            }
        @unknown default:
            .denied
        }
    }
}

private struct BrowserUncheckedSendableNotificationCenter: @unchecked Sendable {
    let value: UNUserNotificationCenter

    init(_ value: UNUserNotificationCenter) {
        self.value = value
    }
}
