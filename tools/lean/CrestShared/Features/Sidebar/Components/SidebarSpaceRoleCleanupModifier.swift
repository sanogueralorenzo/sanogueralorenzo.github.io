import SwiftUI

/// Only a row with a pending editor needs to change its state when its page
/// loses the current role. Ordinary row content does not observe that role.
struct SidebarSpaceRoleCleanupModifier: ViewModifier {
    let isAvailable: Bool
    let hasPendingActions: Bool
    let cancel: () -> Void

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    func body(content: Content) -> some View {
        content.onChange(
            of: SidebarSpaceRole.permitsInteraction(isSelected: isSelected, isAvailable: isAvailable)
        ) { _, isCurrent in
            guard !isCurrent, hasPendingActions else { return }
            cancel()
        }
    }
}
