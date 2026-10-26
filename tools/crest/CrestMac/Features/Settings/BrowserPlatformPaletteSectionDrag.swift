import SwiftUI
import UniformTypeIdentifiers

/// Lets a person drag one of the palette's sections in Settings to a new
/// place. A grouped form on the Mac has no reordering of its own, so the row
/// moves live as it passes over another, and the palette's preferences take
/// each new order as it forms. What follows the pointer is the section's name
/// alone, without the row's controls.
struct BrowserPlatformPaletteSectionDrag: ViewModifier {
    let source: PaletteSource
    @Binding var dragged: PaletteSource?
    /// Moves the section being dragged to where `target` stands.
    let move: (PaletteSource, PaletteSource) -> Void

    func body(content: Content) -> some View {
        content
            .onDrag {
                dragged = source
                return NSItemProvider(object: source.name as NSString)
            } preview: {
                BrowserPaletteSectionDragPreview(source: source)
            }
            .onDrop(of: [.plainText], delegate: Drop(target: source, dragged: $dragged, move: move))
    }

    /// Moves the dragged section over the row it enters, and lets it go on drop.
    private struct Drop: DropDelegate {
        let target: PaletteSource
        @Binding var dragged: PaletteSource?
        let move: (PaletteSource, PaletteSource) -> Void

        func dropEntered(info: DropInfo) {
            guard let dragged, dragged != target else { return }
            withAnimation(.snappy(duration: CrestMotion.hoverTransition)) { move(dragged, target) }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            dragged = nil
            return true
        }
    }
}
