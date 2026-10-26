import AppKit
import Foundation

// MARK: - Types

struct BrowserFileInputOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

@MainActor
final class BrowserDialogPresenter {
    // MARK: - Variables

    /// The window a question attaches to as a sheet: the key or main window,
    /// or Crest's frontmost window while Crest is in the background, so a
    /// question waiting on the person never holds up the rest of Crest, such
    /// as an agent answering a page's dialog.
    private var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
            ?? NSApp.orderedWindows.first { $0.isVisible && $0.canBecomeKey && $0.sheetParent == nil }
    }

    // MARK: - Actions - Script dialogs

    func presentAlert(
        message: String,
        request: URLRequest,
        on window: NSWindow? = nil,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        present(alert, on: window, dismissal: dismissal) { _ in completion() }
    }

    func presentConfirm(
        message: String,
        request: URLRequest,
        on window: NSWindow? = nil,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, on: window, dismissal: dismissal) { completion($0 == .alertFirstButtonReturn) }
    }

    /// Pages no longer choose the wording of a beforeunload prompt, so the
    /// message names the site rather than repeating page-supplied text.
    func presentBeforeUnload(
        request: URLRequest,
        on window: NSWindow? = nil,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Leave this page?"
        alert.informativeText = "Changes you made on \(Self.sourceLabel(for: request)) may not be saved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Leave Page")
        alert.addButton(withTitle: "Stay on Page")
        present(alert, on: window, comesForward: true, dismissal: dismissal) {
            completion($0 == .alertFirstButtonReturn)
        }
    }

    func presentPrompt(
        message: String,
        defaultText: String?,
        request: URLRequest,
        on window: NSWindow? = nil,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, on: window, dismissal: dismissal) { response in
            completion(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    /// The page's server as a dialog names it, which the core formats: its
    /// host, with the port only when it is not the scheme's default.
    static func sourceLabel(for request: URLRequest) -> String {
        guard let url = request.url, let host = url.host(), !host.isEmpty else {
            return ProductIdentity.name
        }
        guard let port = url.port else { return host }
        return AuthenticationSource.label(
            host: host, port: port, scheme: url.scheme, emptyHostLabel: ProductIdentity.name)
    }

    private func makeAlert(message: String, request: URLRequest) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(Self.sourceLabel(for: request)) says"
        alert.informativeText = message
        alert.alertStyle = .informational
        return alert
    }

    // MARK: - Actions - Files

    func presentFileInput(
        options: BrowserFileInputOptions,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose Files for \(Self.sourceLabel(for: request))"
        panel.canChooseFiles = true
        panel.canChooseDirectories = options.allowsDirectories
        panel.allowsMultipleSelection = options.allowsMultipleSelection
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        present(panel) { response in
            completion(response == .OK ? panel.urls : nil)
        }
    }

    func presentFileAccessFailure(
        _ error: Error,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(message: "Crest couldn’t open the selected files.", request: request)
        alert.informativeText = error.localizedDescription
        let denied =
            (error as NSError).domain == NSCocoaErrorDomain
            && (error as NSError).code == CocoaError.fileReadNoPermission.rawValue
        if denied {
            alert.informativeText +=
                " Allow Crest in Privacy & Security > Files and Folders, then choose the files again."
            alert.addButton(withTitle: "Open Files and Folders Settings")
        }
        alert.addButton(withTitle: "OK")
        present(alert) { response in
            if denied, response == .alertFirstButtonReturn,
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
            {
                NSWorkspace.shared.open(url)
            }
            completion()
        }
    }

    // MARK: - Actions - Authentication

    func presentHTTPAuthentication(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String,
        dismissal: BrowserPromptDismissal? = nil
    ) async -> BrowserHTTPAuthenticationPromptResponse? {
        let descriptor = prompt.descriptor
        let alert = NSAlert()
        alert.messageText = "Sign in to \(descriptor.source)"
        alert.informativeText = authenticationMessage(
            prompt: prompt,
            spaceName: spaceName
        )
        alert.alertStyle = descriptor.isSecureTransport ? .informational : .warning

        let username = NSTextField(string: prompt.suggestedUsername ?? "")
        username.placeholderString = "Username"
        username.setAccessibilityLabel("Username")
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        password.setAccessibilityLabel("Password")

        let savePassword = NSButton(
            checkboxWithTitle: "Save in \(spaceName)",
            target: nil,
            action: nil
        )
        savePassword.state = .on
        savePassword.setAccessibilityLabel("Save this sign-in in the \(spaceName) Space")

        let accessoryHeight: CGFloat = prompt.allowsSaving ? 84 : 56
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: accessoryHeight))
        username.frame = NSRect(x: 0, y: accessoryHeight - 24, width: 280, height: 24)
        password.frame = NSRect(x: 0, y: accessoryHeight - 56, width: 280, height: 24)
        fields.addSubview(username)
        fields.addSubview(password)
        if prompt.allowsSaving {
            savePassword.frame = NSRect(x: 0, y: 0, width: 280, height: 20)
            fields.addSubview(savePassword)
        }
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = username

        return await withCheckedContinuation { continuation in
            present(alert, dismissal: dismissal) { response in
                guard response == .alertFirstButtonReturn else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: BrowserHTTPAuthenticationPromptResponse(
                        username: username.stringValue,
                        password: password.stringValue,
                        shouldSave: prompt.allowsSaving && savePassword.state == .on
                    )
                )
            }
        }
    }

    private func authenticationMessage(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String
    ) -> String {
        let descriptor = prompt.descriptor
        var components: [String] = []
        if let realm = descriptor.realm, !realm.isEmpty {
            components.append("Realm: \(realm)")
        }
        if prompt.allowsSaving {
            components.append(
                "This sign-in belongs only to the \(spaceName) Space. "
                    + "Crest saves it only after the site accepts it."
            )
        } else {
            components.append(
                "This sign-in belongs only to the \(spaceName) Space and cannot "
                    + "be saved because the connection is not protected by HTTPS."
            )
        }
        if descriptor.previousFailureCount > 0 {
            components.append("The previous credentials were not accepted.")
        }
        if !descriptor.isSecureTransport {
            components.append("Warning: this connection is not protected by HTTPS.")
        }
        return components.joined(separator: "\n\n")
    }

    // MARK: - Actions - System permissions

    /// Explains the second, app-level permission boundary before leaving Crest.
    /// The caller keeps the page's original request pending, then rechecks the
    /// system authorization after Crest becomes active again.
    func recoverGeolocationSystemAuthorization() async {
        guard
            let settingsURL = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            )
        else { return }
        await presentSystemPermissionRecovery(
            title: "Location Access Is Off for Crest",
            message:
                "macOS is blocking Crest from receiving a location, even when this site is allowed. "
                + "Turn on Crest in Privacy & Security > Location Services. "
                + "This request will continue when you return.",
            openButtonTitle: "Open Location Settings",
            settingsURL: settingsURL
        )
    }

    func recoverNotificationSystemAuthorization() async {
        var components = URLComponents(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: Bundle.main.bundleIdentifier)
        ]
        guard let settingsURL = components?.url else { return }
        await presentSystemPermissionRecovery(
            title: "Notifications Are Off for Crest",
            message:
                "macOS is blocking Crest notifications, even when this site is allowed. "
                + "Turn on Allow notifications for Crest. "
                + "This request will continue when you return.",
            openButtonTitle: "Open Notification Settings",
            settingsURL: settingsURL
        )
    }

    private func presentSystemPermissionRecovery(
        title: String,
        message: String,
        openButtonTitle: String,
        settingsURL: URL
    ) async {
        let shouldOpen = await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: openButtonTitle)
            alert.addButton(withTitle: "Not Now")
            present(alert) { response in
                continuation.resume(
                    returning: response == .alertFirstButtonReturn
                )
            }
        }
        guard shouldOpen, NSWorkspace.shared.open(settingsURL) else { return }
        await waitForApplicationReturn()
    }

    private func waitForApplicationReturn() async {
        var observedInactiveApplication = !NSApp.isActive
        while !observedInactiveApplication {
            try? await Task.sleep(for: .milliseconds(100))
            observedInactiveApplication = !NSApp.isActive
        }
        while !NSApp.isActive {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Actions - External applications

    /// Asks before Crest leaves the browser for another application. Cancelling
    /// is not offered as a saved block, so Escape declines this one hand-off
    /// rather than silently muting the site for good.
    func presentExternalApplicationPermission(
        origin: SiteOrigin,
        destinationURL: URL,
        spaceName: String
    ) async -> BrowserExternalSchemePromptResponse {
        let scheme = destinationURL.scheme?.lowercased() ?? "link"
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Open this “\(scheme)” link in another app?"
            alert.informativeText =
                "\(origin.host) wants to leave Crest and open "
                + "\(Self.externalDestinationLabel(for: destinationURL)). "
                + "The choice belongs only to the \(spaceName) Space and can be "
                + "changed in Settings > Site Permissions."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Always Allow in \(spaceName)")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .open)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .openAndRemember)
                default:
                    continuation.resume(returning: .cancel)
                }
            }
        }
    }

    /// Shows enough of an external URL to judge it without pasting a whole
    /// tracker-laden query string into an alert.
    static func externalDestinationLabel(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        if let host = url.host(), !host.isEmpty {
            return "\(scheme)://\(host)"
        }
        let path = url.absoluteString.dropFirst(scheme.count + 1)
        let trimmed = path.prefix(while: { $0 != "?" })
        return trimmed.isEmpty ? url.absoluteString : "\(scheme):\(trimmed)"
    }

    // MARK: - Actions - Downloads

    func approveRiskyDownload(
        assessment: DownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Download “\(assessment.sanitizedFilename)”?"
            var paragraphs = assessment.reasons.map { String(localized: $0.message) }
            if let host = sourceURL?.host() {
                paragraphs.append("Source: \(host) · Space: \(spaceName)")
            } else {
                paragraphs.append("Space: \(spaceName)")
            }
            paragraphs.append("macOS will quarantine the completed file. Open it only if you trust its source.")
            alert.informativeText = paragraphs.joined(separator: "\n\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

    /// Whether to go on with a download the core judged dangerous, before its
    /// file has a place, or to keep one its engine warned about while it
    /// downloads: the core's reasons, the engine's warning, where it came from
    /// and the Space it belongs to.
    func approveDownload(
        _ asked: DownloadApprovalAsked, spaceName: String?, dismissal: BrowserPromptDismissal? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            let keeps = asked.warning != nil
            alert.messageText = keeps ? "Keep “\(asked.filename)”?" : "Download “\(asked.filename)”?"
            var paragraphs = asked.reasons.map { String(localized: $0.message) }
            if let warning = asked.warning { paragraphs.append(String(localized: warning.approvalMessage)) }
            switch (asked.sourceHost, spaceName) {
            case (let host?, let space?): paragraphs.append("Source: \(host) · Space: \(space)")
            case (let host?, nil): paragraphs.append("Source: \(host)")
            case (nil, let space?): paragraphs.append("Space: \(space)")
            case (nil, nil): break
            }
            if !keeps {
                paragraphs.append("macOS will quarantine the completed file. Open it only if you trust its source.")
            }
            alert.informativeText = paragraphs.joined(separator: "\n\n")
            alert.alertStyle = .warning
            if keeps {
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Keep Download")
            } else {
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Cancel")
            }
            present(alert, dismissal: dismissal) { response in
                continuation.resume(
                    returning: response == (keeps ? .alertSecondButtonReturn : .alertFirstButtonReturn))
            }
        }
    }

    /// Whether `agent`, which macOS vouches for by its code signature, may use
    /// Crest. The question names the program macOS verified, never what the
    /// agent says of itself, except for a general interpreter, whose approval
    /// covers the agent by the name it gives. Crest comes forward, since the
    /// person is likely in the agent's terminal when it asks, and declining is
    /// the default. A `dismissal` closes the question unanswered.
    func approveAgent(
        _ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, dismissal: BrowserPromptDismissal? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = String(localized: "Allow “\(agent.name)” to use Crest?")
            // A signed program is known by its signer; an unsigned one only by
            // where it is.
            var lines =
                agent.signer.map { [String(localized: "Signed by \($0).")] }
                ?? [String(localized: "This program isn’t signed by a developer."), agent.path]
            if agent.isInterpreter, let named = client.map({ Self.shown($0.name) }), !named.isEmpty {
                lines.append(
                    String(
                        localized:
                            "\(agent.name) runs other programs. Allowing it lets any program it runs that calls itself “\(named)” use Crest."
                    ))
            }
            lines.append(
                String(
                    localized:
                        "It can read and act on tabs and history in the Spaces you choose in Settings › Agents, and open windows. Every tab it uses shows its badge."
                ))
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Don’t Allow"))
            alert.addButton(withTitle: String(localized: "Allow"))
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }
            present(alert, comesForward: true, dismissal: dismissal) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    /// Whether the agent may remove every visit to an address from a Space's
    /// history. Keeping the history is the default, and Crest comes forward,
    /// since the person is likely in the agent's terminal when it asks.
    func approveHistoryDeletion(_ deletion: BrowserAgentHistoryDeletion, dismissal: BrowserPromptDismissal? = nil)
        async -> Bool
    {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            let agent = Self.shown(deletion.agentName)
            let space = Self.shown(deletion.spaceName)
            alert.messageText = String(localized: "Let “\(agent)” delete history?")
            alert.informativeText = String(
                localized:
                    "It removes every visit to \(Self.shown(address: deletion.address)) from the \(space) Space’s history."
            )
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Keep History"))
            alert.addButton(withTitle: String(localized: "Delete"))
            alert.buttons[1].hasDestructiveAction = true
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }
            present(alert, comesForward: true, dismissal: dismissal) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    /// Whether the agent may open a window, and whether it may again without
    /// asking until it disconnects. Not opening one is the default, and Crest
    /// comes forward, since the person is likely in the agent's terminal when
    /// it asks.
    func approveWindow(_ opening: BrowserAgentWindowOpening, dismissal: BrowserPromptDismissal? = nil) async
        -> BrowserAgentAnswer
    {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = opening.kind.question(naming: Self.shown(opening.agentName))
            if let detail = opening.kind.detail(
                space: opening.spaceName.map { Self.shown($0) },
                address: opening.address.map { Self.shown(address: $0) })
            {
                alert.informativeText = detail
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Don’t Allow"))
            alert.addButton(withTitle: String(localized: "Allow"))
            alert.showsSuppressionButton = !opening.kind.asksEachTime
            alert.suppressionButton?.title = String(localized: "Don’t ask again until it disconnects")
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }
            present(alert, comesForward: true, dismissal: dismissal) { [weak alert] response in
                guard response == .alertSecondButtonReturn else { return continuation.resume(returning: .declined) }
                let lasts = alert?.suppressionButton?.state == .on
                continuation.resume(returning: lasts ? .whileConnected : .once)
            }
        }
    }

    /// `name` as a question may show it: without control or formatting
    /// characters, such as the ones that reverse text, and at most 64
    /// characters.
    private static func shown(_ name: String) -> String {
        printable(name).split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(64).description
    }

    /// `address` as a question may show it: without control or formatting
    /// characters, and at most 200 characters, cut in the middle.
    private static func shown(address: String) -> String {
        let kept = printable(address)
        guard kept.count > 200 else { return kept }
        return "\(kept.prefix(120))…\(kept.suffix(79))"
    }

    /// `text` without control or formatting characters.
    private static func printable(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        return String(String.UnicodeScalarView(kept))
    }

    /// Whether to quit and stop the `count` downloads still in progress.
    func approveQuitWithDownloads(count: Int, dismissal: BrowserPromptDismissal? = nil) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText =
                count == 1
                ? String(localized: "Quit and cancel the download in progress?")
                : String(localized: "Quit and cancel \(count) downloads in progress?")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Keep Browsing"))
            alert.addButton(withTitle: String(localized: "Quit"))
            present(alert, comesForward: true, dismissal: dismissal) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    // MARK: - Actions - Presentation

    // A `dismissal` closes the sheet once its question no longer waits; the
    // sheet then answers as declined.

    /// Shows `alert` as a sheet on `preferred`, or the window Crest hosts
    /// questions on, or on its own while Crest has none. A question that holds
    /// up leaving a page or quitting `comesForward`: Crest activates first,
    /// so a quit asked from outside it (the updater's relaunch, the Dock, a
    /// logout) never waits on a question the person cannot see.
    private func present(
        _ alert: NSAlert,
        on preferred: NSWindow? = nil,
        comesForward: Bool = false,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        if comesForward, !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard let window = preferred ?? hostWindow else {
            dismissal?.attach { [weak alert] in
                guard let alert, alert.window.isVisible else { return }
                NSApp.stopModal(withCode: .cancel)
            }
            completion(alert.runModal())
            return
        }
        dismissal?.attach { [weak window, weak alert] in
            guard let window, let alert, alert.window.sheetParent === window else { return }
            window.endSheet(alert.window, returnCode: .cancel)
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    private func present(
        _ panel: NSOpenPanel,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = hostWindow else {
            completion(panel.runModal())
            return
        }
        panel.beginSheetModal(for: window, completionHandler: completion)
    }
}
