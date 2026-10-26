import UIKit

/// Completion belongs to the native session that captured it, not the row's
/// latest SwiftUI value. UIKit may report both cancellation and session end.
@MainActor
final class BrowserMobileDragSession {
    let item: UIDragItem
    var provider: NSItemProvider { item.itemProvider }
    weak var source: BrowserMobileDragAnchor?
    var previewShape: BrowserTabDragPreviewShape?
    var isDropping = false
    var previewView: UIView?
    var sourceFrame = CGRect.zero
    private var completion: (() -> Void)?

    init(provider: NSItemProvider, completion: @escaping () -> Void) {
        item = UIDragItem(itemProvider: provider)
        self.completion = completion
    }

    func finish() {
        let action = completion
        completion = nil
        action?()
    }
}
