import SwiftUI

struct BrowserDeveloperCaptureControls: View {
    let page: BrowserPage
    @Binding var showsCaptureOptions: Bool

    var body: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperToolbarButton(
                label: "Capture Window",
                systemImage: "rectangle.inset.filled",
                isActive: showsCaptureOptions,
                action: { showsCaptureOptions.toggle() }
            )
            .disabled(!page.pageEngine.registration.supports(.fullPageCapture))
            .popover(isPresented: $showsCaptureOptions, arrowEdge: .top) {
                BrowserDeveloperCaptureOptions(page: page)
            }

            BrowserDeveloperToolbarButton(
                label: "Capture",
                systemImage: "camera",
                isActive: page.isRegionCapturePresented,
                action: page.beginRegionCapture
            )
            .disabled(!page.pageEngine.registration.supports(.viewportCapture))
        }
    }
}

struct BrowserRegionCaptureOverlay: View {
    /// The shortest side a region capture may have.
    private static let minimumSelectionLength: CGFloat = 12

    let page: BrowserPage

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(.rect)
            .gesture(captureGesture(in: proxy.frame(in: .local)))
            .overlay(alignment: .bottom) {
                BrowserRegionCaptureInstruction()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onExitCommand(perform: page.cancelRegionCapture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page capture selection")
        .accessibilityHint("Drag a rectangle to copy that part of the page")
        .accessibilityIdentifier("developer-region-capture")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        var mask = Path(bounds)
        if let selection = selectionRect(in: bounds) {
            mask.addRect(selection)
        }
        context.fill(
            mask,
            with: .color(.black.opacity(0.46)),
            style: FillStyle(eoFill: true)
        )
        if let selection = selectionRect(in: bounds) {
            context.stroke(
                Path(roundedRect: selection, cornerRadius: 4),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        }
    }

    private func captureGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
                dragEnd = value.location
            }
            .onEnded { value in
                let start = dragStart ?? value.startLocation
                let rect = Self.captureRect(
                    from: start,
                    to: value.location,
                    in: bounds
                )
                dragStart = nil
                dragEnd = nil
                if let rect {
                    page.captureRegion(rect)
                }
            }
    }

    private func selectionRect(in bounds: CGRect) -> CGRect? {
        guard let dragStart, let dragEnd else { return nil }
        return Self.captureRect(
            from: dragStart,
            to: dragEnd,
            in: bounds
        )
    }

    /// The region a drag from `start` to `end` selects, clipped to `bounds`,
    /// or nil when it is too small to be a deliberate selection.
    private static func captureRect(
        from start: CGPoint,
        to end: CGPoint,
        in bounds: CGRect
    ) -> CGRect? {
        let proposed = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let clipped = proposed.intersection(bounds)
        guard !clipped.isNull,
            clipped.width >= minimumSelectionLength,
            clipped.height >= minimumSelectionLength
        else {
            return nil
        }
        return clipped
    }
}

private struct BrowserDeveloperCaptureOptions: View {
    let page: BrowserPage

    var body: some View {
        VStack(spacing: 12) {
            BrowserDeveloperCapturePreview()
            Button(
                "Capture in Portrait Mode",
                systemImage: "rectangle.portrait.on.rectangle.portrait"
            ) {
                page.savePortraitCapture()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            Button(
                "Copy Full Page Capture",
                systemImage: "doc.on.clipboard"
            ) {
                page.copyFullPageCapture()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 260)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture Window")
    }
}

private struct BrowserDeveloperCapturePreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.indigo, .purple, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 112)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.72))
                    .padding(22)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
            .accessibilityHidden(true)
    }
}

private struct BrowserRegionCaptureInstruction: View {
    var body: some View {
        Label(
            "Drag to capture a portion of this page",
            systemImage: "camera.viewfinder"
        )
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background { CrestSurfaceLayer(shape: Capsule()) }
        .padding(.bottom, 28)
        .allowsHitTesting(false)
    }
}
