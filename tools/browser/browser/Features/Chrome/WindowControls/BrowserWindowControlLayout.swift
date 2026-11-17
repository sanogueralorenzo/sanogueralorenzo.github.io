import AppKit

/// Aligns the window's actual controls without opting into a toolbar's larger corners.
@MainActor
final class BrowserWindowControlLayout {
    private let buttons: [(NSButton, Bool, NSRect)]
    private let constraints: [NSLayoutConstraint]

    init?(window: NSWindow) {
        guard let content = window.contentView else { return nil }
        buttons = BrowserNativeWindowControlsHostView.buttonTypes.compactMap { type in
            window.standardWindowButton(type).map { ($0, $0.translatesAutoresizingMaskIntoConstraints, $0.frame) }
        }
        constraints = buttons.enumerated().flatMap { index, entry in
            let button = entry.0
            button.translatesAutoresizingMaskIntoConstraints = false
            return [
                button.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor,
                    constant: SidebarGeometry.inset + SidebarGeometry.titlebarHorizontalInset + CGFloat(index) * 20),
                button.centerYAnchor.constraint(
                    equalTo: content.topAnchor,
                    constant: SidebarGeometry.inset + SidebarGeometry.titlebarHeight / 2),
                button.widthAnchor.constraint(equalToConstant: entry.2.width),
                button.heightAnchor.constraint(equalToConstant: entry.2.height),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    func restore() {
        NSLayoutConstraint.deactivate(constraints)
        for (button, translatesAutoresizingMask, frame) in buttons {
            button.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMask
            button.frame = frame
        }
    }
}
