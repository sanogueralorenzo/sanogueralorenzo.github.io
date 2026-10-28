import SwiftUI

struct BrowserMacDownloadFeedbackLayer: View {
    let model: BrowserRootModel
    let feedback: BrowserMacDownloadFeedbackState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowIdentifier: ObjectIdentifier?

    var body: some View {
        GeometryReader { proxy in
            let root = proxy.frame(in: .global)
            let context = BrowserMacDownloadFeedbackContext(
                windowIdentifier: windowIdentifier,
                profileID: model.browser.shownSpace?.profileID,
                spaceID: model.browser.shownSpace?.id,
                tabID: model.browser.shownTab?.id,
                bounds: root,
                destination: model.sidebarPresentation.showsSidebar
                    ? model.chrome.utilityPresentation.triggerFrameInGlobal : nil,
                isVisible: model.isWindowFocused && !model.chrome.isCommandPalettePresented,
                reduceMotion: reduceMotion
            )
            ZStack(alignment: .topTrailing) {
                ForEach(feedback.flights) { flight in
                    if let path = flight.path {
                        BrowserMacDownloadFlightIcon(
                            path: BrowserMacDownloadFlightPath(
                                source: CGPoint(x: path.source.x - root.minX, y: path.source.y - root.minY),
                                destination: CGPoint(
                                    x: path.destination.x - root.minX, y: path.destination.y - root.minY
                                ),
                                bounds: CGRect(origin: .zero, size: root.size)
                            ),
                            arrive: { feedback.arrive(flight.id) }
                        )
                    }
                }
                if feedback.flights.contains(where: { $0.path == nil }) {
                    Label("Download started", systemImage: "arrow.down.circle")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background { CrestSurfaceLayer(shape: .rect(cornerRadius: 12)) }
                        .padding(.leading, 16)
                        .padding(.bottom, context.destination == nil ? 16 : 56)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .onChange(of: model.pages.downloadCenter.feedbackEvents, initial: true) { _, events in
                reconcile(events: events, context: context)
            }
            .onChange(of: context) { _, context in
                reconcile(events: model.pages.downloadCenter.feedbackEvents, context: context)
            }
        }
        .background(BrowserDownloadFeedbackWindowIdentityReader(identifier: $windowIdentifier))
        .allowsHitTesting(false)
        .onDisappear { feedback.cancel() }
    }

    private func reconcile(
        events: [BrowserDownloadFeedbackEvent],
        context: BrowserMacDownloadFeedbackContext
    ) {
        if feedback.reconcile(events: events, context: context) {
            AccessibilityNotification.Announcement(String(localized: "Download started")).post()
        }
    }
}

private struct BrowserMacDownloadFlightIcon: View {
    let path: BrowserMacDownloadFlightPath
    let arrive: () -> Void
    @State private var progress = 0.0
    @State private var appearance = 0.0

    var body: some View {
        Color.clear
            .modifier(BrowserMacDownloadFlightDrawing(path: path, progress: progress, appearance: appearance))
            .accessibilityHidden(true)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.14), completionCriteria: .logicallyComplete) {
                    appearance = 1
                } completion: {
                    withAnimation(.easeInOut(duration: 0.78).delay(0.1), completionCriteria: .logicallyComplete) {
                        progress = 1
                    } completion: {
                        arrive()
                    }
                }
            }
    }
}

private struct BrowserMacDownloadFlightDrawing: AnimatableModifier {
    let path: BrowserMacDownloadFlightPath
    nonisolated var progress: Double
    nonisolated var appearance: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, appearance) }
        set {
            progress = newValue.first
            appearance = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            Image(systemName: "doc.fill")
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 42, height: 46)
                .background { CrestSurfaceLayer(shape: .rect(cornerRadius: 8)) }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .scaleEffect(path.scale(at: progress) * (0.55 + 0.45 * appearance))
                .opacity(appearance * (1 - min(max((progress - 0.9) / 0.1, 0), 1)))
                .position(path.point(at: progress))
        }
    }
}
