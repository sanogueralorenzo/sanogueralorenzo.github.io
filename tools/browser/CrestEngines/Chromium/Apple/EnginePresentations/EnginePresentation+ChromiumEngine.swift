#if CREST_CHROMIUM_HOST
    import Foundation

    extension EnginePresentation {
        /// Hands the presentation to what it concerns on the Chromium engine, as
        /// the presentation's own `present(on:)` says. One for a page that is
        /// gone, or that its owner let go, changes nothing.
        @MainActor func present(on engine: ChromiumEngine) {
            switch self {
            case .audioSpectrumChanged(let presentation): presentation.present(on: engine)
            case .contentFullscreenChanged(let presentation): presentation.present(on: engine)
            case .contentMessagePosted(let presentation): presentation.present(on: engine)
            case .contentScriptEvaluated(let presentation): presentation.present(on: engine)
            case .extensionsChanged(let presentation): presentation.present(on: engine)
            case .infoBarRemoved(let presentation): presentation.present(on: engine)
            case .infoBarShown(let presentation): presentation.present(on: engine)
            case .inspectorClosed(let presentation): presentation.present(on: engine)
            case .inspectorLayoutChanged(let presentation): presentation.present(on: engine)
            case .linkHovered(let presentation): presentation.present(on: engine)
            case .mediaSessionChanged(let presentation): presentation.present(on: engine)
            case .pageInteracted(let presentation): presentation.present(on: engine)
            case .pageLoadingChanged(let presentation): presentation.present(on: engine)
            case .pageNavigationCommitted(let presentation): presentation.present(on: engine)
            case .pageNavigationFailed(let presentation): presentation.present(on: engine)
            case .pageNavigationStarted(let presentation): presentation.present(on: engine)
            case .pageRendererGone(let presentation): presentation.present(on: engine)
            case .pageThemeChanged(let presentation): presentation.present(on: engine)
            case .pageViewClosed(let presentation): presentation.present(on: engine)
            case .pageViewReady(let presentation): presentation.present(on: engine)
            case .pageViewUnavailable(let presentation): presentation.present(on: engine)
            case .peekRequested(let presentation): presentation.present(on: engine)
            case .popupBlocked(let presentation): presentation.present(on: engine)
            case .profilePrepared(let presentation): presentation.present(on: engine)
            case .profileNotificationPosted(let presentation): presentation.present(on: engine)
            case .profileNotificationClosed(let presentation): presentation.present(on: engine)
            case .profileReleased(let presentation): presentation.present(on: engine)
            case .screenCaptureAccessMissing(let presentation): presentation.present(on: engine)
            case .shareSourcesOffered(let presentation): presentation.present(on: engine)
            case .shareSourcesWithdrawn(let presentation): presentation.present(on: engine)
            case .tabSharingChanged(let presentation): presentation.present(on: engine)
            case .sidePanelRequested(let presentation): presentation.present(on: engine)
            case .storeInstallRequested(let presentation): presentation.present(on: engine)
            case .storeRemovalRequested(let presentation): presentation.present(on: engine)
            case .webNotificationClosed(let presentation): presentation.present(on: engine)
            case .webNotificationPosted(let presentation): presentation.present(on: engine)
            case .findFinished, .pageCaptured, .pageExported, .pageScriptEvaluated, .pageInputDelivered:
                // The page's shared direct path hears what it asked for.
                break
            }
        }
    }
#endif
