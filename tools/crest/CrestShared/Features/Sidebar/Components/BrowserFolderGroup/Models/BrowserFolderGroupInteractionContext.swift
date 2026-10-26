import SwiftUI

/// The state a saved folder group keeps between events, and the moves its
/// parts may make, handed down together so a component reads only what it
/// needs to draw.
struct BrowserFolderGroupInteractionContext {
    let isExpanded: Binding<Bool>
    let editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?>
    let draftTitle: Binding<String>
    let collapsedTabVisibility: Binding<BrowserCollapsedFolderTabVisibilityState>
    let isTitleFocused: FocusState<Bool>.Binding
    let beginCreatingChild: () -> Void
    let beginRenaming: () -> Void
    let toggleExpansion: () -> Void
    let beginTitleEditingIfNeeded: () -> Void
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void
    let deleteFolder: () -> Void
}
