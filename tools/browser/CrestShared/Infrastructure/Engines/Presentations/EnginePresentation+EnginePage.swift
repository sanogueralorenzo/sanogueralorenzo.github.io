import Foundation

extension EnginePresentation {
    /// Hands the presentation to the shared page it is about, as the
    /// presentation's own `deliver(to:)` says.
    @MainActor func deliver(to page: EnginePage) {
        switch self {
        case .findFinished(let presentation): presentation.deliver(to: page)
        case .pageCaptured(let presentation): presentation.deliver(to: page)
        case .pageExported(let presentation): presentation.deliver(to: page)
        case .pageInputDelivered(let presentation): presentation.deliver(to: page)
        case .pageNavigationCommitted(let presentation): presentation.deliver(to: page)
        case .pageNavigationFailed(let presentation): presentation.deliver(to: page)
        case .pageScriptEvaluated(let presentation): presentation.deliver(to: page)
        case .pageViewReady(let presentation): presentation.deliver(to: page)
        case .audioSpectrumChanged, .contentFullscreenChanged, .contentMessagePosted, .contentScriptEvaluated,
            .extensionsChanged, .infoBarRemoved, .infoBarShown, .inspectorClosed, .inspectorLayoutChanged,
            .linkHovered, .mediaSessionChanged, .pageInteracted, .pageLoadingChanged,
            .pageNavigationStarted, .pageRendererGone, .pageThemeChanged, .pageViewClosed, .pageViewUnavailable,
            .peekRequested, .popupBlocked, .profileNotificationClosed, .profileNotificationPosted, .profilePrepared,
            .profileReleased, .screenCaptureAccessMissing, .shareSourcesOffered, .shareSourcesWithdrawn,
            .sidePanelRequested, .storeInstallRequested, .storeRemovalRequested, .tabSharingChanged,
            .webNotificationClosed, .webNotificationPosted:
            // The shared page waits for none of these; its engine's own page
            // hears them.
            break
        }
    }
}
