import AppKit
import SecurityInterface

@MainActor
enum BrowserSiteCertificatePresenter {
    static func present(trust: SecTrust, for window: NSWindow?) {
        guard let panel = SFCertificatePanel.shared() else { return }
        panel.setDefaultButtonTitle(String(localized: "Done"))

        guard let window else {
            panel.runModal(for: trust, showGroup: true)
            return
        }

        panel.beginSheet(
            for: window,
            modalDelegate: nil,
            didEnd: nil,
            contextInfo: nil,
            trust: trust,
            showGroup: true
        )
    }
}
