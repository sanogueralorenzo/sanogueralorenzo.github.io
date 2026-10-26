import Foundation
import SwiftUI

struct BrowserRootLifecycleModifier: ViewModifier {
    let model: BrowserRootModel
    let persistSidebarWidth: (Double) -> Void
    @Binding var storedSidebarWidth: Double

    init(
        model: BrowserRootModel,
        storedSidebarWidth: Binding<Double>,
        persistSidebarWidth: @escaping (Double) -> Void = { _ in }
    ) {
        self.model = model
        self.persistSidebarWidth = persistSidebarWidth
        _storedSidebarWidth = storedSidebarWidth
    }

    /// Each observer reads only the state it follows in a modifier of its
    /// own, so showing another tab re-evaluates the observers of the
    /// selection, the page and the session, and leaves the rest of the
    /// window's lifecycle, and the content below it, as it was.
    func body(content: Content) -> some View {
        content
            .task {
                await model.prepareBrowser()
            }
            .modifier(BrowserRootWindowFocusObserver(model: model))
            .modifier(BrowserRootSelectionFollower(model: model))
            .modifier(BrowserRootPageMetadataObserver(model: model))
            .modifier(BrowserRootSessionFollower(model: model))
            .modifier(
                BrowserRootChromeObserver(
                    model: model,
                    storedSidebarWidth: $storedSidebarWidth,
                    persistSidebarWidth: persistSidebarWidth
                )
            )
    }
}

private struct BrowserRootWindowFocusObserver: ViewModifier {
    let model: BrowserRootModel

    func body(content: Content) -> some View {
        content.onChange(of: model.isWindowFocused, initial: true) { _, isFocused in
            model.hostWindowFocusChanged(isFocused)
        }
    }
}

private struct BrowserRootSelectionFollower: ViewModifier {
    let model: BrowserRootModel

    func body(content: Content) -> some View {
        content.modifier(
            BrowserRootSelectionObserver(
                selection: model.selectionSnapshot,
                lock: model.selectedSpaceIsLocked,
                // A window with no locked-Space arrangement of its own has
                // nothing to do about a lock that is already up when it
                // appears; `prepareBrowser` settles that case.
                evaluatesLockInitially: false,
                selectionChanged: synchronizeSelection,
                lockChanged: { _, _ in
                    model.synchronizeAfterLockChange()
                }
            )
        )
    }

    /// A Space change and a tab change are different work, so the transition is
    /// split here rather than inside the observer: moving Space resets the
    /// address field and leaves the page swap to the content selection policy,
    /// while a tab change performs it.
    private func synchronizeSelection(
        _ previous: BrowserRootSelectionSnapshot,
        _ current: BrowserRootSelectionSnapshot
    ) {
        if previous.spaceID != current.spaceID {
            model.synchronizeAfterSpaceChange()
        } else if previous.tabID != current.tabID {
            model.synchronizeAfterSelectionChange()
        }
    }
}

private struct BrowserRootPageMetadataObserver: ViewModifier {
    let model: BrowserRootModel

    func body(content: Content) -> some View {
        content
            .onChange(of: model.browser.shownTab?.url) { model.synchronizePageMetadata() }
            .onChange(of: model.pages.activePage?.live.displayURL) {
                model.synchronizePageMetadata()
            }
    }
}

private struct BrowserRootSessionFollower: ViewModifier {
    let model: BrowserRootModel
    @State private var runtimeSessionProjection: BrowserRuntimeSessionProjection

    init(model: BrowserRootModel) {
        self.model = model
        _runtimeSessionProjection = State(initialValue: model.pages.runtimeProjection)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: model.browser.sessionRevision, initial: true) {
                model.browser.followSession()
                runtimeSessionProjection = model.pages.runtimeProjection
                model.reconcilePages()
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
            .onChange(
                of: runtimeSessionProjection.credentialAccessState,
                initial: true
            ) {
                model.reconcileCredentialAccess()
            }
    }
}

private struct BrowserRootChromeObserver: ViewModifier {
    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double
    let persistSidebarWidth: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: storedSidebarWidth) { _, width in
                model.restoreSidebarWidth(CGFloat(width))
                persistSidebarWidth(width)
            }
            .onChange(of: model.chrome.columnVisibility) {
                model.columnVisibilityChanged(reduceMotion: reduceMotion)
            }
            .onChange(of: model.chrome.isFloatingSidebarPresented) {
                model.floatingSidebarPresentationChanged()
            }
            .onChange(of: model.lockedSpaceIDs, initial: true) { _, spaceIDs in
                model.relockProtectedSpaces(spaceIDs)
            }
    }
}
