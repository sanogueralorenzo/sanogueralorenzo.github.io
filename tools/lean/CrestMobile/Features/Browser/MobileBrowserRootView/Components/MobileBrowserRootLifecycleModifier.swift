import Foundation
import SwiftUI

struct MobileBrowserRootLifecycleModifier: ViewModifier {
    let model: MobileBrowserRootModel
    let presentation: MobileBrowserPresentation
    @Binding var isAddressEditing: Bool
    @Binding var storedSidebarWidth: Double
    @State private var runtimeSessionProjection: BrowserRuntimeSessionProjection
    /// Which tab belongs to which Space and profile. Page residency is what this
    /// drives, so it changes only when a tab is added, removed, or moved — not
    /// when one of them merely finishes a navigation.
    @State private var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment>

    init(
        model: MobileBrowserRootModel,
        presentation: MobileBrowserPresentation,
        isAddressEditing: Binding<Bool>,
        storedSidebarWidth: Binding<Double>
    ) {
        self.model = model
        self.presentation = presentation
        _isAddressEditing = isAddressEditing
        _storedSidebarWidth = storedSidebarWidth
        _runtimeSessionProjection = State(
            initialValue: model.pages.runtimeProjection
        )
        _tabRuntimeAssignments = State(
            initialValue: model.pages.tabRuntimeAssignments
        )
    }

    func body(content: Content) -> some View {
        let preparedContent =
            content
            .task {
                await model.prepareBrowser()
            }
            .modifier(
                BrowserRootSelectionObserver(
                    selection: model.selectionSnapshot,
                    selectionChanged: synchronizeSelection
                )
            )

        let pageObservedContent =
            preparedContent
            .onChange(of: model.selectedPage?.live.displayURL) {
                synchronizePageMetadata()
            }
            .onChange(of: isAddressEditing) { _, isEditing in
                guard !isEditing else { return }
                model.restoreAddress()
            }

        let runtimeObservedContent =
            pageObservedContent
            .onChange(of: model.browser.sessionRevision, initial: true) {
                model.browser.followSession()
                runtimeSessionProjection = model.pages.runtimeProjection
                tabRuntimeAssignments =
                    model.pages.tabRuntimeAssignments
            }
            .onChange(of: tabRuntimeAssignments, initial: true) {
                model.reconcileResidentPages()
            }
            .onChange(
                of: runtimeSessionProjection.tabIconState,
                initial: true
            ) {
                model.reconcileTabIcons()
            }
            .onChange(
                of: runtimeSessionProjection.contentBlockingState,
                initial: true
            ) {
                model.reconcileContentBlocking()
            }

        return
            runtimeObservedContent
            .onChange(of: storedSidebarWidth) { _, width in
                model.restoreSidebarWidth(CGFloat(width))
            }
            .onChange(
                of: model.navigation.regularSidebarPresentation
            ) { _, presentation in
                model.regularSidebarPresentationChanged(presentation)
            }
    }

    private func synchronizeSelection(
        _ previous: MobileBrowserRootSelectionSnapshot,
        _ current: MobileBrowserRootSelectionSnapshot
    ) {
        guard model.synchronizeSelection(from: previous, to: current) else {
            return
        }
        isAddressEditing = false
        BrowserAddressFocusDismissal.dismiss()
    }

    private func synchronizePageMetadata() {
        model.synchronizePageMetadata(isAddressEditing: isAddressEditing)
    }
}
