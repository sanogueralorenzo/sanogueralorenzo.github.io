import AppKit

@MainActor
final class BrowserCredentialClipboard {
    private static var live: BrowserCredentialClipboard?

    private let pasteboard: any BrowserCredentialPasteboard
    private let notificationCenter: NotificationCenter
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (Duration) async throws -> Void
    private var expirationTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var leasedChangeCount: Int?

    init(
        pasteboard: any BrowserCredentialPasteboard,
        notificationCenter: NotificationCenter,
        now: @escaping @MainActor () -> Date,
        sleep: @escaping @MainActor (Duration) async throws -> Void
    ) {
        self.pasteboard = pasteboard
        self.notificationCenter = notificationCenter
        self.now = now
        self.sleep = sleep
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearIfUnchanged()
            }
        }
    }

    isolated deinit {
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
        expirationTask?.cancel()
    }

    static func write(_ lease: BrowserCredentialSecretLease) -> Bool {
        let clipboard: BrowserCredentialClipboard
        if let live {
            clipboard = live
        } else {
            clipboard = BrowserCredentialClipboard(
                pasteboard: BrowserSystemCredentialPasteboard(
                    pasteboard: .general
                ),
                notificationCenter: .default,
                now: { .now },
                sleep: { try await Task.sleep(for: $0) }
            )
            live = clipboard
        }
        return clipboard.write(lease)
    }

    func write(_ lease: BrowserCredentialSecretLease) -> Bool {
        guard let password = lease.password(at: now()),
            pasteboard.writeConcealedTransientString(password)
        else { return false }

        expirationTask?.cancel()
        let changeCount = pasteboard.changeCount
        leasedChangeCount = changeCount
        let expiration = lease.expiration
        expirationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, expiration.timeIntervalSince(now()))
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled,
                leasedChangeCount == changeCount,
                pasteboard.changeCount == changeCount
            else { return }
            leasedChangeCount = nil
            pasteboard.clearContents()
        }
        return true
    }

    private func clearIfUnchanged() {
        guard let leasedChangeCount,
            pasteboard.changeCount == leasedChangeCount
        else { return }
        self.leasedChangeCount = nil
        expirationTask?.cancel()
        expirationTask = nil
        pasteboard.clearContents()
    }
}
