import AppKit
import SwiftUI

struct BrowserRootUtilityFanLayer: View {
    let model: BrowserRootModel
    var sidebarOnRight = false

    @State private var visibleTriggerFrame: CGRect?

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrame = model.chrome.utilityPresentation
                .triggerFrameInGlobal
            {
                let rootFrame = proxy.frame(in: .global)
                let localTriggerFrame = triggerFrame.offsetBy(
                    dx: -rootFrame.minX,
                    dy: -rootFrame.minY
                )
                BrowserRootUtilityFanControl(
                    model: model,
                    proxy: proxy,
                    localTriggerFrame:
                        model.sidebarPresentation.reservesSidebarWidth
                        ? localTriggerFrame : visibleTriggerFrame ?? localTriggerFrame,
                    sidebarOnRight: sidebarOnRight
                )
                .onChange(of: localTriggerFrame, initial: true) { _, frame in
                    guard !model.sidebarPresentation.reservesSidebarWidth,
                        model.sidebarPresentation.showsSidebar
                    else { return }
                    visibleTriggerFrame = frame
                }
            }
        }
        .animation(nil, value: model.sidebarPresentation)
    }
}

/// Reads the identity of the window it is in, and takes up no space there.
///
/// AppKit hands cursor updates to the topmost view under the pointer, even
/// one SwiftUI does not hit-test, and a view that answers none passes them up
/// to the hosting view, which shows the arrow. Over a page, a reader the size
/// of its layer would put the arrow back each time the page changed its
/// cursor, so a video's hidden cursor would never stay hidden.
struct BrowserDownloadFeedbackWindowIdentityReader: NSViewRepresentable {
    @Binding var identifier: ObjectIdentifier?

    func makeCoordinator() -> Coordinator {
        Coordinator(identifier: $identifier)
    }

    func makeNSView(context: Context) -> WindowIdentityView {
        let view = WindowIdentityView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.set(window.map(ObjectIdentifier.init))
        }
        return view
    }

    func updateNSView(_ nsView: WindowIdentityView, context: Context) {
        context.coordinator.identifier = $identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WindowIdentityView, context: Context) -> CGSize? {
        .zero
    }

    final class Coordinator {
        var identifier: Binding<ObjectIdentifier?>

        init(identifier: Binding<ObjectIdentifier?>) {
            self.identifier = identifier
        }

        func set(_ value: ObjectIdentifier?) {
            guard identifier.wrappedValue != value else { return }
            identifier.wrappedValue = value
        }
    }

    final class WindowIdentityView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}
