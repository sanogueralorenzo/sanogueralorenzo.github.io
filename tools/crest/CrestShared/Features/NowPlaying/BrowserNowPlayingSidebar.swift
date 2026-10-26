import SwiftUI

extension EnvironmentValues {
    @Entry var browserMediaSessions: BrowserMediaSessionStore? = nil
}

/// The active browser media session, shared across regular Spaces.
struct BrowserNowPlayingSidebar: View {
    // MARK: - Variables

    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    @Environment(\.browserMediaSessions) private var store

    // MARK: - Actions - Content

    var body: some View {
        if let store, let session = MediaSessionOrder.arbitration(of: store.sidebarSessions)?.nowPlaying {
            BrowserNowPlayingRow(
                store: store, session: session, faviconData: ownerFaviconData(session.owner),
                activate: activateMediaSession
            )
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.top, CrestSpacing.medium)
            .padding(.bottom, CrestSpacing.extraSmall)
            .accessibilityElement(children: .contain)
        }
    }
}
