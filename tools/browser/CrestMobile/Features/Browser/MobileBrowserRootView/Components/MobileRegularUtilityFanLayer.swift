import SwiftUI
import UIKit

struct MobileRegularUtilityFanLayer: View {
    @Environment(\.browserChromeAppearance) private var appearance
    let layout: MobileRegularWindowLayout
    let layoutDirection: LayoutDirection
    let triggerFrameInGlobal: CGRect?
    let sidebarIsPresented: Bool
    let isExpanded: Bool
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [DownloadState]
    let newDownloadCount: Int
    let downloadCenter: BrowserDownloadCenter
    let profileID: UUID?
    let spaceID: UUID?
    let select: (BrowserUtilitySurface) -> Void

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrameInGlobal, sidebarIsPresented {
                let rootFrame = proxy.frame(in: .global)
                let localTriggerFrame = triggerFrameInGlobal.offsetBy(
                    dx: -rootFrame.minX,
                    dy: -rootFrame.minY
                )
                let edgeOffset =
                    BrowserUtilitySwitcherLayout.buttonSize / 2
                    + BrowserUtilitySwitcherLayout.destinationGap
                let destinationX =
                    appearance.sidebarOnRight
                    ? proxy.size.width - layout.sidebarWidth - edgeOffset
                    : layout.sidebarWidth + edgeOffset

                BrowserUtilityFanControl(
                    isExpanded: isExpanded,
                    origin: CGPoint(
                        x: localTriggerFrame.midX,
                        y: localTriggerFrame.midY
                    ),
                    destination: CGPoint(
                        x: destinationX,
                        y: proxy.size.height / 2
                    ),
                    selectedSurface: selectedSurface,
                    badgeColor: badgeColor,
                    downloads: downloads,
                    newDownloadCount: newDownloadCount,
                    select: select
                )
                .zIndex(MobileBrowserRootLayout.utilityLayer)

                BrowserDownloadFeedbackLayer(
                    events: downloadCenter.feedbackEvents,
                    profileID: profileID,
                    spaceID: spaceID,
                    destinationFrameInGlobal: triggerFrameInGlobal
                )
                .zIndex(MobileBrowserRootLayout.utilityLayer + 1)
            }
        }
    }
}

struct BrowserDownloadFeedbackWindowIdentityReader: UIViewRepresentable {
    @Binding var identifier: ObjectIdentifier?

    func makeCoordinator() -> Coordinator {
        Coordinator(identifier: $identifier)
    }

    func makeUIView(context: Context) -> WindowIdentityView {
        let view = WindowIdentityView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.set(window.map(ObjectIdentifier.init))
        }
        return view
    }

    func updateUIView(_ uiView: WindowIdentityView, context: Context) {
        context.coordinator.identifier = $identifier
    }

    final class Coordinator {
        var identifier: Binding<ObjectIdentifier?>

        init(identifier: Binding<ObjectIdentifier?>) {
            self.identifier = identifier
        }

        func set(_ value: ObjectIdentifier?) {
            guard identifier.wrappedValue != value else { return }
            identifier.wrappedValue = value
        }
    }

    final class WindowIdentityView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }
}
