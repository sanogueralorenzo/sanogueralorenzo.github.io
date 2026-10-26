import SwiftUI

struct BrowserPeekUnlockedContent: View {
    let model: BrowserPeekModel
    let reservedLeadingWidth: CGFloat
    let layoutDirection: LayoutDirection
    let installsKeyboardMonitor: Bool

    init(
        model: BrowserPeekModel,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection,
        installsKeyboardMonitor: Bool = true
    ) {
        self.model = model
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.installsKeyboardMonitor = installsKeyboardMonitor
        _retainedMotionState = State(initialValue: model.motionState)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var retainedMotionState: BrowserPeekMotionState?

    var body: some View {
        BrowserTransientSurface(
            state: presentationState,
            pageStatus: pageStatus,
            spaces: model.availableSpaceModels.map(\.identity),
            selectedSpaceID: model.request.spaceID,
            vocabulary: BrowserPeekVocabulary.overlay,
            actions: actions
        ) {
            webContent
        }
        .modifier(taskLifecycle)
        .allowsHitTesting(!model.isPullStaged)
        .onChange(of: model.motionState) { _, state in
            if let state { retainedMotionState = state }
        }
        .task(id: model.motionState?.releasedAt) {
            guard model.motionState?.returnsToSource == true else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 1.2))
            guard !Task.isCancelled else { return }
            model.finishReturningPull()
        }
        .modifier(
            BrowserPeekInputLifecycleModifier(
                model: model,
                dismiss: dismiss,
                installsKeyboardMonitor: installsKeyboardMonitor
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peek from \(model.request.sourceTitle)")
    }

    /// The window's own web content, handed to the shared card. The page and
    /// the pool that owns it are macOS types, so they never cross into the
    /// shared surface.
    @ViewBuilder
    private var webContent: some View {
        if let page = model.page, let pages = model.pages {
            BrowserWebContentView(
                page: page,
                browser: model.browser,
                pages: pages
            )
        }
    }

    private var presentationState: BrowserTransientPresentationState {
        BrowserTransientPresentationState(
            arrangement: .pointer,
            reservedLeadingWidth: reservedLeadingWidth,
            layoutDirection: layoutDirection,
            isCardVisible: true,
            isCardExpanded: !model.isPullStaged,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            presentationPhase: model.isPullStaged ? .staged : .committed,
            sourcePresentation: .resolved(model.request.sourcePresentation),
            // Keep the outgoing card and its presentation intact while
            // the coordinator removes the request and SwiftUI fades it out.
            motionState: model.motionState ?? retainedMotionState
        )
    }

    private var pageStatus: BrowserTransientPageStatus {
        BrowserTransientPageStatus(
            hasPage: model.page != nil && model.pages != nil,
            wasReleasedForMemoryPressure:
                model.pageLease?.wasReleasedForMemoryPressure == true,
            initialLoadingCoverLabel: showsInitialLoadingSurface
                ? BrowserPeekVocabulary.initialLoadingCoverLabel
                : nil
        )
    }

    private var actions: BrowserTransientCardActions {
        BrowserTransientCardActions(
            dismiss: dismiss,
            promote: promote,
            restore: model.restorePage
        )
    }

    /// Whether the card still has to cover a page that has been handed a URL
    /// but has painted nothing. A page that failed has its own thing to say.
    private var showsInitialLoadingSurface: Bool {
        guard let page = model.page else { return false }
        return page.committedNavigationCount == 0
            && page.live.failure == nil
            && page.webContentFailureMessage == nil
    }

    private var taskLifecycle: BrowserPeekTaskLifecycleModifier {
        BrowserPeekTaskLifecycleModifier(requestID: model.request.id, present: presentCard)
    }

    private func presentCard() async {
        _ = model.preparePage(isActive: scenePhase == .active)
    }

    private func dismiss() {
        withAnimation(dismissAnimation) {
            model.dismiss()
        }
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        _ = model.promote(to: assignment)
    }

    private var dismissAnimation: Animation? {
        CrestMotion.peekDismissal.unlessReducingMotion(reduceMotion)
    }
}
