import SwiftUI

struct BrowserWebPageSurface: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pagePresentation: PagePresentation
    /// Whether the window's page commands act on this page: a Peek open over
    /// the active tab, or else the tab's own page. That page alone takes the
    /// keyboard, for its find bar and as focus returns to it, so the tab
    /// under an open Peek never takes it from the Peek.
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate
    /// Where the tab holding a page sits in its Space and what it is called,
    /// for lists that follow the sidebar.
    var tabPlacement: (UUID) -> BrowserShareSourceOffer.TabPlacement? = { _ in nil }
    /// Shows the tab at the other end of the page's tab sharing, when Crest
    /// knows it; the sharing bars lead there.
    var goToSharingCounterpart: (() -> Void)? = nil

    /// The agent using the page's tab now, when one does.
    private var agent: AgentSessionState? {
        guard let tabID = browser.core.state.pages[page.corePage.id]?.tabID else { return nil }
        return browser.core.state.agentSessions.first { $0.tabIDs.contains(tabID) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            BrowserPlatformWebView(
                page: page,
                isPageActive: isPageActive,
                focusRestorationGate: focusRestorationGate
            )
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { _ in
                (page.nativeView as? any BrowserNativePageSurfaceLifecycle)?.presentationGeometryDidChange()
            }
            .accessibilityLabel(page.live.title.isEmpty ? "Web page" : page.live.title)
            .opacity(
                BrowserPageSurfacePresentation.revealsWebContent(
                    committedNavigationCount: page.committedNavigationCount
                ) ? 1 : 0
            )

            BrowserPageLoadingPresentation(page: page)

            if let hover = page.linkHover { BrowserLinkHoverPreview(hover: hover) }

            if page.isFindPresented {
                BrowserFindBar(
                    port: findPort,
                    capabilities: capabilities,
                    isPageActive: isPageActive
                )
                .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }

            if !page.visibleEngineInfoBars.isEmpty {
                BrowserEngineInfoBarStack(page: page, goToSharingCounterpart: goToSharingCounterpart)
            }

            if let agent, let pointer = page.agentPointer {
                BrowserAgentPointerOverlay(pointer: pointer, session: agent, zoom: page.renderedPageZoom)
                    .zIndex(BrowserWebPageSurfaceMetrics.agentPointerZIndex)
            }

            if let agent {
                BrowserAgentPageBar(session: agent) {
                    if let tabID = browser.core.state.pages[page.corePage.id]?.tabID {
                        _ = try? browser.core.send(StopAgentTab(tabID: tabID))
                    }
                }
                .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }

            BrowserWebPageFailureOverlay(
                page: page,
                branding: browser.spaceModel(
                    matching: BrowserSpaceRuntimeAssignment(spaceID: page.spaceID, profileID: page.profileID)
                ).map(\.settings.look),
                pagePresentation: pagePresentation
            )

            BrowserCredentialChrome(
                presentation: BrowserCredentialChromePresentation.resolve(
                    saveCandidate: page.credentialSaveCandidate,
                    fillRequest: page.credentialFillRequest
                ),
                fillPort: credentialFillPort,
                savePort: credentialSavePort,
                browser: browser,
                capabilities: capabilities
            )

            if page.isRegionCapturePresented {
                BrowserRegionCaptureOverlay(page: page)
                    .zIndex(BrowserWebPageSurfaceMetrics.regionCaptureZIndex)
            }

            if let offer = page.shareSourceOffer {
                BrowserShareSourcePicker(
                    offer: offer, requestingPageID: page.corePage.id, tabPlacement: tabPlacement,
                    requestingTabName: tabPlacement(page.corePage.id)?.name ?? page.live.title
                ) { choice in
                    page.answer(offer, with: choice)
                }
                .id(offer.id)
                .zIndex(BrowserWebPageSurfaceMetrics.sharePickerZIndex)
            }

            if let feedback = page.developerCaptureFeedback {
                BrowserDeveloperCaptureFeedbackView(feedback: feedback)
                    .zIndex(BrowserWebPageSurfaceMetrics.feedbackZIndex)
            }
        }
    }

    /// The questions the find bar asks, bound to this surface's page.
    private var findPort: BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            query: { page.findQuery },
            matchState: { page.findMatchState },
            matches: { page.findMatches },
            focusRequest: { page.findFocusRequest },
            focusesQueryField: { page.findFocusesQueryField },
            dismiss: page.dismissFind
        )
    }

    /// What a credential fill prompt asks of this surface's page.
    ///
    /// The zoom is carried because this shell anchors the prompt under the
    /// field that raised it, and the page reports that field in its own CSS
    /// pixels. The chrome is a sibling of the web view inside one box, so the
    /// zoom is the only thing between the two.
    private var credentialFillPort: BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            contentScale: page.renderedPageZoom,
            siteIconData: page.faviconData,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of this surface's page. This shell makes no
    /// offer to the system's Passwords app, so it binds none.
    private var credentialSavePort: BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: nil
        )
    }

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}

private struct BrowserPageLoadingPresentation: View {
    /// How long a page's first load runs before the surface says it is
    /// opening. A load that finishes sooner goes straight from the page
    /// before to the page, as a browser's does, with nothing in between.
    private static let initialLoadingStatusDelay: Duration = .milliseconds(400)

    let page: BrowserPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the first load has run long enough to say the page is opening.
    @State private var initialStatusIsDue = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showsInitialStatus, initialStatusIsDue {
                    initialStatus
                }
            }
            .task(id: showsInitialStatus) {
                initialStatusIsDue = false
                guard showsInitialStatus else { return }
                try? await Task.sleep(for: Self.initialLoadingStatusDelay)
                guard !Task.isCancelled else { return }
                initialStatusIsDue = true
            }
            .overlay(alignment: .top) {
                loadingProgress
            }
            .allowsHitTesting(false)
    }

    private var initialStatus: some View {
        VStack(spacing: BrowserWebPageSurfaceMetrics.initialLoadingSpacing) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            openingLabel
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("browser-initial-loading-status")
    }

    private var loadingProgress: some View {
        Rectangle()
            .fill(.tint)
            .frame(height: BrowserWebPageSurfaceMetrics.loadingProgressHeight)
            .scaleEffect(x: progress, anchor: .leading)
            .opacity(isNavigating ? 1 : 0)
            .animation(
                CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion),
                value: progress
            )
            .accessibilityHidden(true)
    }

    private var openingLabel: Text {
        guard let host = page.live.displayURL?.host(), !host.isEmpty else {
            return Text(
                "Opening page…",
                comment: "Initial status while a web page begins navigating."
            )
        }
        return Text(
            "Opening \(host)…",
            comment: "Initial page loading status; the value is the destination host."
        )
    }

    private var isNavigating: Bool {
        // Same-document destinations can remain pending without a WebKit load.
        // Only use the destination to bridge a fresh page's initial loading gap.
        page.live.isLoading || (page.live.pendingNavigationURL != nil && page.committedNavigationCount == 0)
    }

    private var hasFailure: Bool {
        page.live.failure != nil || page.webContentFailureMessage != nil
    }

    private var showsInitialStatus: Bool {
        isNavigating && page.committedNavigationCount == 0 && !hasFailure
    }

    private var progress: CGFloat {
        BrowserPageSurfacePresentation.loadingProgress(
            estimatedProgress: page.estimatedProgress,
            isNavigating: isNavigating
        )
    }
}
