import SwiftUI

extension EnvironmentValues {
    @Entry var browserSidebarWidgetRuntime: BrowserSidebarWidgetRuntime? = nil
    @Entry var browserApplicationIcon: Image? = nil
}

/// Presents the application widget deck independently of the selected Space.
struct BrowserSidebarWidgetHost: View {
    /// Whether a sidebar shows the deck: only while it is presented, and never
    /// in a private window.
    static func isShown(
        sidebarIsPresented: Bool,
        isPrivateBrowsing: Bool
    ) -> Bool {
        sidebarIsPresented && !isPrivateBrowsing
    }

    let capabilities: BrowserSidebarWidgetCapabilities
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserSidebarWidgetRuntime) private var runtime
    @State private var visibleInstanceID: BrowserSidebarWidgetID?

    var body: some View {
        if !instances.isEmpty {
            BrowserSidebarWidgetDeck(
                instances: instances,
                selectedInstanceID: visibleInstanceID,
                perform: perform,
                activateMediaSession: activateMediaSession,
                ownerFaviconData: ownerFaviconData,
                cycle: cycle
            )
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .overlay(alignment: .trailing) {
                if instances.count > 1 {
                    BrowserSidebarWidgetDeckStepper(
                        instances: instances,
                        selectedInstanceID: visibleInstanceID,
                        select: select,
                        cycle: cycle
                    )
                    .frame(width: BrowserSidebarWidgetDeckStyle.sideStepperRailWidth)
                    .offset(
                        x: BrowserSidebarWidgetDeckStyle.sideStepperExternalOffset
                    )
                }
            }
            .padding(.top, CrestSpacing.small)
            .padding(.bottom, CrestSpacing.extraSmall)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sidebar Widgets")
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
            .onChange(of: instanceIDs, initial: true) {
                reconcileSelection()
            }
            .onChange(of: runtimeSelection) { _, selectedID in
                guard selectedID != visibleInstanceID else { return }
                withAnimation(deckAnimation) {
                    visibleInstanceID = selectedID
                }
            }
            .onChange(of: visibleInstanceID) { _, selectedID in
                guard let selectedID, selectedID != runtimeSelection else {
                    return
                }
                runtime?.selectCarouselInstance(
                    selectedID,
                    visibleInstances: instances
                )
            }
        }
    }

    private var instances: [BrowserSidebarWidgetInstance] {
        runtime?.instances(capabilities: capabilities) ?? []
    }

    private var instanceIDs: [BrowserSidebarWidgetID] {
        instances.map(\.id)
    }

    private var runtimeSelection: BrowserSidebarWidgetID? {
        runtime?.carouselSelection
    }

    private var deckAnimation: Animation? {
        CrestMotion.spaceSwipe.unlessReducingMotion(reduceMotion)
    }

    private func reconcileSelection() {
        withAnimation(deckAnimation) {
            runtime?.reconcileCarouselSelection(visibleInstances: instances)
            visibleInstanceID = runtime?.carouselSelection ?? instances.first?.id
        }
    }

    private func select(_ instanceID: BrowserSidebarWidgetID) {
        guard instanceID != visibleInstanceID else { return }
        withAnimation(deckAnimation) {
            runtime?.selectCarouselInstance(
                instanceID,
                visibleInstances: instances
            )
            visibleInstanceID = instanceID
        }
    }

    private func cycle(_ direction: BrowserSidebarWidgetCarouselDirection) {
        guard
            let nextID = direction.adjacentID(to: visibleInstanceID, in: instances)
        else { return }
        select(nextID)
    }

    private func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        runtime?.perform(action, on: instanceID)
    }
}
