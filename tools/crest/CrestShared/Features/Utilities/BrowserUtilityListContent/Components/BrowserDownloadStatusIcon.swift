import SwiftUI

struct BrowserDownloadStatusIcon: View {
    let item: DownloadState

    var body: some View {
        if let symbol = item.phase.symbol {
            Image(systemName: symbol).foregroundStyle(symbolStyle)
        } else if item.phase.isTransferring {
            ZStack {
                Image(systemName: BrowserDownloadFileKind(filename: item.filename).symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(item.progress, 0.02))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Download Progress")
            .accessibilityValue(
                Text(
                    item.progress,
                    format: .percent.precision(.fractionLength(0))
                )
            )
        } else if item.phase.isLive {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: BrowserDownloadFileKind(filename: item.filename).symbol)
        }
    }

    /// A decision the person owes reads as a caution, trouble as an error, and
    /// anything else stays quiet.
    private var symbolStyle: AnyShapeStyle {
        if item.phase.awaitsDecision {
            AnyShapeStyle(Color.orange)
        } else if item.phase.needsAttention {
            AnyShapeStyle(Color.red)
        } else {
            AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}

/// Decorative, bounded feedback for a trusted link activation becoming a
/// download. The durable affordance remains the Downloads badge and row; this
/// layer never receives hit testing or accessibility focus.
struct BrowserDownloadFeedbackLayer: View {
    let events: [BrowserDownloadFeedbackEvent]
    let profileID: UUID?
    let spaceID: UUID?
    let destinationFrameInGlobal: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowIdentifier: ObjectIdentifier?

    var body: some View {
        GeometryReader { proxy in
            if let destinationFrameInGlobal {
                let rootFrame = proxy.frame(in: .global)
                let destination = CGPoint(
                    x: destinationFrameInGlobal.midX - rootFrame.minX,
                    y: destinationFrameInGlobal.midY - rootFrame.minY
                )
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) {
                    index,
                    event in
                    if rootFrame.insetBy(dx: -36, dy: -36).contains(
                        event.source.pointInGlobal
                    ) {
                        BrowserDownloadFeedbackIcon(
                            filename: event.filename,
                            source: CGPoint(
                                x: event.source.pointInGlobal.x - rootFrame.minX,
                                y: event.source.pointInGlobal.y - rootFrame.minY
                            ),
                            destination: CGPoint(
                                x: destination.x - CGFloat(index) * 4,
                                y: destination.y - CGFloat(index) * 4
                            ),
                            presentation: BrowserDownloadFeedbackPresentation.resolve(
                                hasSource: true,
                                hasSidebarDestination: true,
                                reduceMotion: reduceMotion
                            )
                        )
                    }
                }
            }
        }
        .background(
            BrowserDownloadFeedbackWindowIdentityReader(
                identifier: $windowIdentifier
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var visibleEvents: [BrowserDownloadFeedbackEvent] {
        events.filter { event in
            guard event.profileID == profileID else { return false }
            guard event.spaceID == spaceID else { return false }
            guard let windowIdentifier else { return false }
            return event.source.windowIdentifier == windowIdentifier
        }
    }
}

private struct BrowserDownloadFeedbackIcon: View {
    let filename: String
    let source: CGPoint
    let destination: CGPoint
    let presentation: BrowserDownloadFeedbackPresentation

    @State private var hasArrived = false

    var body: some View {
        icon
            .position(position)
            .opacity(opacity)
            .scaleEffect(scale)
            .task {
                await Task.yield()
                guard let arrival = presentation.arrival else { return }
                withAnimation(arrival) {
                    hasArrived = true
                }
            }
    }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: BrowserDownloadFileKind(filename: filename).symbol)
                .font(.system(size: 21, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .tint)
                .offset(x: 3, y: 3)
        }
        .foregroundStyle(.primary)
        .frame(width: 36, height: 36)
        .background { CrestSurfaceLayer(shape: .rect(cornerRadius: 9)) }
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private var position: CGPoint {
        presentation.departsFromSource && !hasArrived ? source : destination
    }

    private var opacity: Double {
        presentation.opacity(hasArrived: hasArrived)
    }

    private var scale: CGFloat {
        presentation.scale(hasArrived: hasArrived)
    }
}

#if DEBUG
    #Preview("Download states") {
        HStack(spacing: 20) {
            BrowserDownloadStatusIcon(item: BrowserUtilityListPreviewFixture.preparingDownload)
            BrowserDownloadStatusIcon(item: BrowserUtilityListPreviewFixture.activeDownload)
            BrowserDownloadStatusIcon(item: BrowserUtilityListPreviewFixture.finishedDownload)
            BrowserDownloadStatusIcon(item: BrowserUtilityListPreviewFixture.failedDownload)
        }.padding()
    }
#endif
