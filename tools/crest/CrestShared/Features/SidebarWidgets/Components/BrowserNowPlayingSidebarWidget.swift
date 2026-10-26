import SwiftUI

struct BrowserNowPlayingSidebarWidget: View {
    let instance: BrowserSidebarWidgetInstance
    let session: BrowserMediaSessionSnapshot
    let faviconData: Data?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activate: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var artworkSize =
        BrowserSidebarWidgetDeckStyle.artworkSize
    @ScaledMetric(relativeTo: .footnote) private var faviconSize =
        BrowserSidebarWidgetDeckStyle.faviconSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            mediaIdentityButton
                .padding(
                    .top,
                    BrowserSidebarWidgetDeckStyle.nowPlayingSectionSpacing
                )
            transportRow
                .padding(
                    .top,
                    BrowserSidebarWidgetDeckStyle.nowPlayingSectionSpacing
                )
        }
        .overlay(alignment: .topTrailing) {
            // Reserve the touch target without increasing the title row height.
            dismissButton
        }
        .padding(.top, -CrestSpacing.extraSmall)
        .accessibilityLabel("Now Playing")
    }

    /// Keeps tab activation and dismissal in separate hit targets.
    private var headerRow: some View {
        Button {
            showOwner()
        } label: {
            Text(verbatim: session.ownerDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(
                    minHeight: BrowserSidebarWidgetDeckStyle.quietControlDiameter,
                    alignment: .leading
                )
                .padding(
                    .trailing,
                    BrowserSidebarWidgetDeckStyle.quietControlDiameter
                        + CrestSpacing.extraSmall
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show tab \(session.ownerDisplayTitle)")
        .help("Show Tab")
    }

    private var mediaIdentityButton: some View {
        Button {
            showOwner()
        } label: {
            HStack(spacing: CrestSpacing.small) {
                artwork

                VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                    Text(verbatim: session.mediaDisplayTitle)
                        .font(CrestTypography.metadata.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: session.secondaryMetadata ?? "Media from this tab")
                        .font(CrestTypography.compactMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .crestHoverSurface(cornerRadius: CrestRadius.compact)
        .accessibilityLabel("Show tab playing \(session.displayTitle)")
        .help("Show Tab")
    }

    @ViewBuilder
    private var dismissButton: some View {
        if instance.availableActions.contains(.dismissMediaSession) {
            Button {
                perform(.dismissMediaSession, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(
                BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing)
            )
            .accessibilityLabel("Hide Now Playing")
            .help("Hide until this tab plays again")
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkData = session.artworkData,
            let image = BrowserSidebarWidgetArtwork.image(from: artworkData)
        {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .compositingGroup()
                .clipShape(artworkShape)
                .frame(width: artworkSize, height: artworkSize)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: artworkSize, height: artworkSize)
                .background(.quaternary, in: artworkShape)
                .overlay { hairline(artworkShape) }
                .accessibilityHidden(true)
        }
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserSidebarWidgetDeckStyle.artworkCornerRadius,
            style: .continuous
        )
    }

    private func hairline(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            Color.primary.opacity(
                BrowserSidebarWidgetDeckStyle.hairlineStrokeOpacity
            ),
            lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
        )
    }

    /// Centers transport controls between the tab and volume actions.
    private var transportRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                cornerSlot { ownerFaviconButton }
                Spacer(minLength: 0)
                HStack(spacing: CrestSpacing.small) {
                    transportButton(
                        .previousTrack,
                        symbol: "backward.fill",
                        label: "Previous Track"
                    )
                    playbackButton
                    transportButton(
                        .nextTrack,
                        symbol: "forward.fill",
                        label: "Next Track"
                    )
                }
                Spacer(minLength: 0)
                cornerSlot { volumeButton }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                cornerSlot { ownerFaviconButton }
                Spacer(minLength: 0)
                playbackButton
                Spacer(minLength: 0)
                cornerSlot { volumeButton }
            }
            .frame(maxWidth: .infinity)

            playbackButton
                .frame(maxWidth: .infinity)
        }
    }

    private func cornerSlot(
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget
            )
    }

    private var ownerFaviconButton: some View {
        Button {
            showOwner()
        } label: {
            faviconContent
                .frame(width: faviconSize, height: faviconSize)
        }
        .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
        .accessibilityLabel("Show tab playing \(session.displayTitle)")
        .help("Show Tab")
    }

    private func showOwner() {
        activate(session.owner)
    }

    @ViewBuilder
    private var faviconContent: some View {
        if let faviconData,
            let image = BrowserSidebarWidgetArtwork.image(from: faviconData)
        {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var volumeButton: some View {
        if instance.availableActions.contains(.toggleMute) {
            Button {
                perform(.toggleMute, instance.id)
            } label: {
                Image(
                    systemName: session.isMuted
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                .contentTransition(.symbolEffect(.replace))
                .animation(pressAnimation, value: session.isMuted)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
            .accessibilityValue(session.isMuted ? Text("Muted") : Text("Unmuted"))
            .help(session.isMuted ? "Unmute" : "Mute")
        }
    }

    @ViewBuilder
    private var playbackButton: some View {
        let isPlaying =
            session.playbackState == .playing
            && instance.availableActions.contains(.pause)
        let action: BrowserSidebarWidgetAction = isPlaying ? .pause : .play
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(
                        width: BrowserSidebarWidgetDeckStyle.focalControlDiameter,
                        height: BrowserSidebarWidgetDeckStyle.focalControlDiameter
                    )
                    .contentShape(.circle)
                    .animation(pressAnimation, value: isPlaying)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget
            )
            .contentShape(.circle)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause" : "Play")
        }
    }

    @ViewBuilder
    private func transportButton(
        _ action: BrowserSidebarWidgetAction,
        symbol: String,
        label: LocalizedStringKey
    ) -> some View {
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: symbol)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(label)
            .help(label)
        }
    }

    private var pressAnimation: Animation? {
        CrestMotion.press.unlessReducingMotion(reduceMotion)
    }
}
