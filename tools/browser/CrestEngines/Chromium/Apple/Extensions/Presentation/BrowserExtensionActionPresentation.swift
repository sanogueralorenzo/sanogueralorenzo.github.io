import AppKit

@MainActor
struct BrowserExtensionActionPresentation: Identifiable {
    let id: String
    let displayName: String
    let badgeText: String
    let icon: NSImage?
    let isEnabled: Bool
    let isPinned: Bool
    let isLoading: Bool

    init(
        id: String,
        displayName: String,
        badgeText: String = "",
        icon: NSImage? = nil,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.badgeText = badgeText
        self.icon = icon
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.isLoading = isLoading
    }

}

extension BrowserExtensionActionPresentation {
    /// An action as the engine lists it.
    init(_ action: ExtensionAction) {
        self.init(
            id: action.id, displayName: action.name, badgeText: action.badge,
            icon: action.icon.flatMap(NSImage.init(extensionIcon:)), isEnabled: action.enabled,
            isPinned: action.pinned)
    }
}

extension NSImage {
    /// An extension's icon, which the engine encodes at twice its size in points.
    convenience init?(extensionIcon data: Data) {
        self.init(data: data)
        size = NSSize(width: size.width / 2, height: size.height / 2)
    }
}
