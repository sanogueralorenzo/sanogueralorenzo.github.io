import SwiftUI
import UIKit

/// Registers the existing SwiftUI row as a native drag source. The anchor draws
/// nothing and receives no touches; one host interaction arbitrates native
/// dragging with the row's existing buttons, scrolling, and context menu.
struct BrowserMobileDragSource<Preview: View>: UIViewRepresentable {
    var previewShape: BrowserTabDragPreviewShape?
    let begin: () -> BrowserMobileDragSession
    @ViewBuilder let preview: (CGFloat) -> Preview

    func makeUIView(context: Context) -> BrowserMobileDragAnchor {
        let view = BrowserMobileDragAnchor()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: BrowserMobileDragAnchor, context: Context) {
        view.begin = begin
        let environment = context.environment
        view.makePreview = { width, scale in
            let renderer = ImageRenderer(
                content: preview(width)
                    .frame(width: previewShape == nil ? width : nil)
                    .environment(\.self, environment))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            renderer.scale = scale
            return UIImageView(image: renderer.uiImage)
        }
        view.previewShape = previewShape
        view.connect()
        view.refreshPreview()
    }
}

final class BrowserMobileDragAnchor: UIView {
    var begin: (() -> BrowserMobileDragSession)?
    var makePreview: ((CGFloat, CGFloat) -> UIView)?
    var previewShape: BrowserTabDragPreviewShape?
    private weak var router: BrowserMobileDragRouter?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    func refreshPreview() {
        router?.refreshPreview(for: self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        connect()
    }

    func connect() {
        guard let window else {
            router?.remove(self)
            router = nil
            return
        }
        var ancestor = superview
        while let view = ancestor, !view.interactions.contains(where: { $0 is UIContextMenuInteraction }) {
            ancestor = view.superview
        }
        // UIKit pairs drag and context-menu interactions on the same view.
        // Discover the public interaction, without depending on a hosting class.
        let next = BrowserMobileDragRouter.forView(ancestor ?? window)
        guard router !== next else { return }
        router?.remove(self)
        next.add(self)
        router = next
    }

    /// Clipping and hidden ancestors matter for offscreen rows and Space pages.
    func visibleFrame(in window: UIWindow) -> CGRect {
        var frame = convert(bounds, to: window)
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0 else { return .null }
            if view.clipsToBounds {
                frame = frame.intersection(view.convert(view.bounds, to: window))
            }
            ancestor = view.superview
        }
        return frame.intersection(window.bounds)
    }
}

extension View {
    func browserMobileDraggable<Preview: View>(
        previewShape: BrowserTabDragPreviewShape? = nil,
        begin: @escaping () -> BrowserMobileDragSession,
        @ViewBuilder preview: @escaping (CGFloat) -> Preview
    ) -> some View {
        background(BrowserMobileDragSource(previewShape: previewShape, begin: begin, preview: preview))
    }
}
