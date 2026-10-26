import CoreImage
import SwiftUI

/// Only processed pixels reach the locked surface. It never mounts a WebKit
/// view, and a missing snapshot leaves the opaque access screen in place.
struct LockedSpacePagePreview: View {
    let space: SpaceModel
    /// The tabs the window shows side by side in `space`.
    let cards: [TabStateModel]
    let pages: BrowserPagePool
    @State private var images: [UUID: CGImage] = [:]

    var body: some View {
        HStack(spacing: BrowserChromeLayout.pageBrandSeamWidth) {
            ForEach(cards) { tab in
                GeometryReader { geometry in
                    if let image = images[tab.id] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: BrowserSpaceRuntimeAssignment(space: space)) {
            var obscured: [UUID: CGImage] = [:]
            for tab in cards {
                guard !Task.isCancelled else { return }
                guard
                    let page = pages.residentPage(
                        matching: BrowserTabRuntimeAssignment(
                            tabID: tab.id, spaceID: space.id, profileID: space.profileID)),
                    let image = await snapshot(page)
                else { continue }
                let blurred = await Task.detached(priority: .utility) { Self.obscure(image) }.value
                guard !Task.isCancelled else { return }
                obscured[tab.id] = blurred
            }
            images = obscured
        }
    }

    private func snapshot(_ page: BrowserPage) async -> CGImage? {
        return await withCheckedContinuation { continuation in
            page.captureViewport(width: 256) { image in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    nonisolated private static func obscure(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24])
            .cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }
}
