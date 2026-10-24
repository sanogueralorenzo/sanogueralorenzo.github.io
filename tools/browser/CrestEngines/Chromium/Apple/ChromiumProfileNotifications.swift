#if CREST_CHROMIUM_HOST
    import AppKit
    import Foundation

    /// Worker and extension notifications live with their profile while the
    /// app runs. Every delivery and click rechecks the core's access decision.
    @MainActor
    final class ChromiumProfileNotifications {
        // MARK: - Types

        private struct Posted {
            let generation: UUID
            let notification: ProfileNotificationPosted
        }

        // MARK: - Variables

        private let core: CrestCore
        private let center: any BrowserHostedWebNotificationCentering
        private let pages: NativeEnginePages
        private var posted: [String: Posted] = [:]

        // MARK: - Initializers

        init(core: CrestCore, center: any BrowserHostedWebNotificationCentering, pages: NativeEnginePages) {
            self.core = core
            self.center = center
            self.pages = pages
            core.followNotificationAccess(self) { [weak self] in self?.withdrawInaccessible() }
        }

        // MARK: - Actions - Delivery

        func show(_ notification: ProfileNotificationPosted) {
            let identifier = identifier(profileID: notification.profileID, notificationID: notification.notificationID)
            guard allows(notification), posted[identifier] != nil || posted.count < 256 else {
                answer(notification, .declined)
                return
            }
            let generation = UUID()
            if let previous = posted[identifier] {
                remove(identifier, previous.generation)
            }
            posted[identifier] = Posted(generation: generation, notification: notification)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard await center.currentAuthorization() == .authorized, isCurrent(identifier, generation) else {
                    decline(identifier, generation)
                    return
                }
                do {
                    try await center.add(
                        BrowserHostedWebNotificationDelivery(
                            identifier: systemIdentifier(identifier, generation),
                            title: String(notification.title.prefix(200)),
                            body: String(notification.body.prefix(1_000)), origin: notification.origin,
                            isSilent: notification.silent)
                    ) { [weak self] _ in
                        guard let self, isCurrent(identifier, generation) else { return }
                        posted.removeValue(forKey: identifier)
                        NSApp.activate()
                        answer(notification, .clicked)
                    }
                    // Revocation or replacement can race system delivery.
                    if !isCurrent(identifier, generation) {
                        decline(identifier, generation)
                        await center.remove(identifier: systemIdentifier(identifier, generation))
                    }
                } catch {
                    decline(identifier, generation)
                }
            }
        }

        func withdraw(profileID: UUID, notificationID: String) {
            let identifier = identifier(profileID: profileID, notificationID: notificationID)
            guard let item = posted.removeValue(forKey: identifier) else { return }
            remove(identifier, item.generation)
        }

        // MARK: - Actions - Authorization

        private func allows(_ notification: ProfileNotificationPosted) -> Bool {
            (try? core.query(
                ProfileNotificationDisplayCheck(
                    profileID: notification.profileID, origin: notification.origin, source: notification.source)
            ))?.shows == true
        }

        private func isCurrent(_ identifier: String, _ generation: UUID) -> Bool {
            guard let item = posted[identifier], item.generation == generation else { return false }
            return allows(item.notification)
        }

        private func withdrawInaccessible() {
            for (identifier, item) in posted where !allows(item.notification) {
                decline(identifier, item.generation)
            }
        }

        private func decline(_ identifier: String, _ generation: UUID) {
            guard let item = posted[identifier], item.generation == generation else { return }
            posted.removeValue(forKey: identifier)
            answer(item.notification, .declined)
            remove(identifier, generation)
        }

        private func remove(_ identifier: String, _ generation: UUID) {
            let systemIdentifier = systemIdentifier(identifier, generation)
            Task { @MainActor [center] in await center.remove(identifier: systemIdentifier) }
        }

        private func systemIdentifier(_ identifier: String, _ generation: UUID) -> String {
            "\(identifier).\(generation.uuidString)"
        }

        private func answer(_ notification: ProfileNotificationPosted, _ answer: WebNotificationAnswer) {
            pages.request(
                AnswerProfileNotification(
                    profileID: notification.profileID, notificationID: notification.notificationID, answer: answer))
        }

        private func identifier(profileID: UUID, notificationID: String) -> String {
            "profile.\(profileID.uuidString).\(notificationID)"
        }
    }
#endif
