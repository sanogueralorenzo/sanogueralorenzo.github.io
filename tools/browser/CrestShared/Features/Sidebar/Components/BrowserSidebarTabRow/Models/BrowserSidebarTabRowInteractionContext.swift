import SwiftUI

/// The live half of a sidebar tab row: the state it keeps between events and
/// the actions its parts trigger.
///
/// Kept apart from `BrowserSidebarTabRowConfiguration` so the row's pieces can
/// take the bindings they need without any of them owning the state.
struct BrowserSidebarTabRowInteractionContext {
    let isHovering: Binding<Bool>
    let isDropTargeted: Binding<Bool>
    /// The row's measured height, which the drop indicators size against on a
    /// shell that draws them.
    let dropTargetHeight: Binding<CGFloat>
    let isRenaming: Bool
    let draftTitle: Binding<String>
    let isTitleFocused: FocusState<Bool>.Binding
    let isChoosingIcon: Binding<Bool>
    let activate: () -> Void
    let beginRenaming: () -> Void
    let beginChangingIcon: () -> Void
    let setEmojiIcon: (String) -> Void
    let resetIcon: () -> Void
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void
    /// Isolated because the platform seam that delivers an auxiliary click
    /// hands it straight to a main-actor gesture recognizer.
    let dismissFromAuxiliaryClick: @MainActor () -> Void
}
