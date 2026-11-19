import AppKit

/// Position the native controls without adding a toolbar that enlarges the window corners.
@MainActor
final class BrowserWindowControlLayout {
    private struct Placement {
        let button: NSButton
        let frame: NSRect
        let autoresizes: Bool
        let isHidden: Bool
        let leading: CGFloat
        let constraint: NSLayoutConstraint
    }

    private let placements: [Placement]
    private let constraints: [NSLayoutConstraint]

    init?(window: NSWindow) {
        guard let content = window.contentView else { return nil }
        placements = BrowserNativeWindowControlsHostView.buttonTypes.enumerated().compactMap { index, type in
            guard let button = window.standardWindowButton(type) else { return nil }
            let leading = SidebarGeometry.inset + SidebarGeometry.titlebarHorizontalInset + CGFloat(index) * 20
            return Placement(
                button: button, frame: button.frame, autoresizes: button.translatesAutoresizingMaskIntoConstraints,
                isHidden: button.isHidden, leading: leading,
                constraint: button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: leading))
        }
        constraints = placements.flatMap { placement in
            let button = placement.button
            button.translatesAutoresizingMaskIntoConstraints = false
            return [
                placement.constraint,
                button.centerYAnchor.constraint(
                    equalTo: content.topAnchor,
                    constant: SidebarGeometry.inset + SidebarGeometry.titlebarHeight / 2),
                button.widthAnchor.constraint(equalToConstant: placement.frame.width),
                button.heightAnchor.constraint(equalToConstant: placement.frame.height),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    func update(sidebarOffset: CGFloat) {
        for placement in placements {
            let leading = placement.leading + sidebarOffset
            if placement.constraint.constant != leading { placement.constraint.constant = leading }
            let isHidden = leading + placement.frame.width <= 0
            if placement.button.isHidden != isHidden { placement.button.isHidden = isHidden }
        }
    }

    func restore() {
        NSLayoutConstraint.deactivate(constraints)
        for placement in placements {
            placement.button.translatesAutoresizingMaskIntoConstraints = placement.autoresizes
            placement.button.frame = placement.frame
            placement.button.isHidden = placement.isHidden
        }
    }
}
