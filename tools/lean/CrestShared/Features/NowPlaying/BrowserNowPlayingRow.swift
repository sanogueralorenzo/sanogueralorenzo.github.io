import SwiftUI

struct BrowserNowPlayingRow: View {
    // MARK: - Variables

    let store: BrowserMediaSessionStore
    let session: BrowserMediaSessionSnapshot
    let faviconData: Data?
    let activate: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var artworkSize = 22

    // MARK: - Actions - Content

    var body: some View {
        HStack(spacing: 0) {
            mediaIdentityButton
            transportButton(.previousTrack, symbol: "backward.fill", label: "Previous Track")
            playbackButton
            transportButton(.nextTrack, symbol: "forward.fill", label: "Next Track")
        }
        .padding(.trailing, capabilities.tabRowMetrics.contentTrailingInset)
        .frame(minHeight: capabilities.rowMinHeight(dynamicTypeSize: dynamicTypeSize))
        .crestHoverSurface(cornerRadius: BrowserSidebarMetrics.layerCornerRadius())
        .background {
            CrestSurfaceLayer(
                shape: RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius()),
                tint: CrestColor.chromeSurface
            )
        }
        .contextMenu {
            if session.playbackState != .none {
                Button {
                    store.toggleMute(of: session.id)
                } label: {
                    Label(
                        session.isMuted ? String(localized: "Unmute") : String(localized: "Mute"),
                        systemImage: session.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                }
            }
            Button {
                store.dismissCard(of: session.id)
            } label: {
                Label("Hide Now Playing", systemImage: "xmark")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    private var mediaIdentityButton: some View {
        Button {
            activate(session.owner)
        } label: {
            HStack(spacing: CrestSpacing.small) {
                artwork
                    .frame(width: capabilities.tabRowMetrics.faviconSlot?.width)
                Text(verbatim: session.displayTitle)
                    .modifier(BrowserSidebarDensityFont(scale: 1, supportsTouch: capabilities.supportsTouch))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, capabilities.tabRowMetrics.contentLeadingInset)
            .padding(.trailing, CrestSpacing.extraSmall)
            .frame(minHeight: capabilities.rowMinHeight(dynamicTypeSize: dynamicTypeSize))
            .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: BrowserSidebarMetrics.layerCornerRadius())
        )
        .accessibilityLabel("Show tab playing \(session.displayTitle)")
        .help("Show Tab")
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = session.artworkData ?? faviconData,
            let image = BrowserNowPlayingArtwork.image(from: data)
        {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(.rect(cornerRadius: CrestRadius.compact / 2))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: artworkSize, height: artworkSize)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var playbackButton: some View {
        let isPlaying = session.playbackState == .playing && session.availableActions.contains(.pause)
        transportButton(
            isPlaying ? .pause : .play,
            symbol: isPlaying ? "pause.fill" : "play.fill",
            label: isPlaying ? "Pause" : "Play"
        )
    }

    @ViewBuilder
    private func transportButton(
        _ action: MediaSessionAction, symbol: String, label: LocalizedStringKey
    ) -> some View {
        if session.availableActions.contains(action) {
            Button {
                store.perform(action, on: session.id)
            } label: {
                Image(systemName: symbol)
                    .font(
                        .system(
                            size: capabilities.trailingControlMetrics.glyphSize,
                            weight: capabilities.trailingControlMetrics.glyphWeight
                        )
                    )
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: capabilities.trailingControlMetrics.controlSize))
            .accessibilityLabel(label)
            .help(label)
        }
    }
}

#if DEBUG
    #Preview("Compact Now Playing") {
        let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        BrowserNowPlayingRow(
            store: BrowserMediaSessionStore(),
            session: BrowserMediaSessionSnapshot(
                id: BrowserMediaSessionID(tabID: id, documentIdentifier: "preview"),
                owner: BrowserTabRuntimeAssignment(tabID: id, spaceID: id, profileID: id),
                ownerTitle: "Music",
                title: "A long track title that stays on one line",
                artist: nil,
                album: nil,
                artworkData: nil,
                playbackState: .playing,
                isAudible: true,
                isMuted: false,
                availableActions: [.play, .pause, .previousTrack, .nextTrack],
                orderingOrdinal: 1
            ),
            faviconData: nil,
            activate: { _ in }
        )
        .padding(CrestSpacing.small)
        .frame(width: 280)
    }
#endif
