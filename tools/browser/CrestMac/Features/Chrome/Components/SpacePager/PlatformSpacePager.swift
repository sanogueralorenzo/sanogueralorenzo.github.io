import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var spacePagerContentTopInsets: [UUID: CGFloat] = [:]
}

/// SwiftUI supplies semantic state and content. AppKit owns only sidebar motion.
struct PlatformSpacePager<Content: View>: NSViewRepresentable {
    let spaces: [SpaceModel]
    let selectedSpaceID: UUID
    let isInteractionLocked: Bool
    let spaceStep: BrowserSpaceStep?
    let selectSpace: (UUID) -> UUID
    @ViewBuilder let content: (SpaceModel, Bool) -> Content

    private var pageEnvironment = SpacePageEnvironment()

    func makeNSView(context: Context) -> SpacePagerViewport<Content> {
        SpacePagerViewport(frame: .zero)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: SpacePagerViewport<Content>, context: Context
    ) -> CGSize? {
        // The shell determines the viewport; retained pages fill that size.
        // Avoid native fitting traversing those page subtrees whenever their
        // scroll geometry changes.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: SpacePagerViewport<Content>, context: Context) {
        let environment = context.environment
        let objects = pageEnvironment.objects
        view.update(
            spaces: spaces, selectedSpaceID: selectedSpaceID,
            isInteractionLocked: isInteractionLocked,
            spaceStep: spaceStep,
            reduceMotion: environment.accessibilityReduceMotion,
            layoutDirection: environment.layoutDirection,
            presentation: environment.spacePagerPresentation,
            contentTopInsets: environment.spacePagerContentTopInsets,
            selectSpace: selectSpace
        ) { space, isSelected in
            SpacePageRoot(
                content: content(space, isSelected),
                assignment: BrowserSpaceRuntimeAssignment(space: space), objects: objects)
        }
    }

    static func dismantleNSView(_ view: SpacePagerViewport<Content>, coordinator: ()) {
        view.teardown()
    }
}
