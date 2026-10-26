import AppKit
import SwiftUI

/// Presentation is independent of selection: both sides of a slide need their
/// content, but neither may own input until the selected page has settled.
enum SpaceContentPresentation {
    case inactive
    case preview
    case interactive
}

extension EnvironmentValues {
    @Entry var spaceContentPresentation = SpaceContentPresentation.interactive
}

/// The hosting view inherits its environment through the representable's native
/// hierarchy. Copying the parent's entire EnvironmentValues back into this root
/// duplicates propagation through every row on native geometry/focus updates.
/// Only the window's shared objects travel with the root, because views require
/// them and a page can be built before it has inherited them.
struct SpacePageRoot<Content: View>: View {
    let content: Content
    let assignment: BrowserSpaceRuntimeAssignment
    let objects: SpacePageObjects
    var contentPresentation = SpaceContentPresentation.interactive

    var body: some View {
        content
            .id(assignment)
            .environment(\.spaceContentPresentation, contentPresentation)
            .environment(objects.sidebarInteraction)
            .environment(objects.extensionSidePanel)
            .environment(objects.downloadFeedback)
            .environment(objects.passkeyAccess)
            .environment(objects.softwareUpdates)
            .environment(objects.agentEndpoint)
            .environment(objects.core)
    }
}

@MainActor
final class SpacePageHost<Content: View>: NSView {
    let hostingView: NSHostingView<SpacePageRoot<Content>>

    init(root: SpacePageRoot<Content>) {
        hostingView = NSHostingView(rootView: root)
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        if hostingView.frame != bounds { hostingView.frame = bounds }
    }
}
