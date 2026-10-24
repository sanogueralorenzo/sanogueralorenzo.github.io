import SwiftUI

struct TabFaviconView: View {
    let subject: BrowserTabFaviconSubject
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    @State private var renderState = BrowserFaviconRenderState()
    @Environment(\.browserSpaceContentIsLocked) private var isLocked

    init(subject: BrowserTabFaviconSubject, profileID: UUID? = nil, size: CGFloat = TabFaviconMetrics.defaultSize) {
        self.subject = subject
        self.profileID = profileID
        self.size = size
    }

    var body: some View {
        let request = subject.renderRequest(
            profileID: profileID, maximumPixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size),
            isUnlocked: !isLocked)
        TabFaviconContent(
            subject: subject,
            size: size,
            requestIdentity: request.identity,
            renderedImage: renderState.renderedImage
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: request.identity) {
            await loadRenderedImage(for: request)
        }
    }

    private func loadRenderedImage(for request: BrowserFaviconRenderRequest) async {
        guard !Task.isCancelled else { return }
        renderState.begin(request.identity, isCancelled: Task.isCancelled)
        guard !Task.isCancelled else { return }
        guard let image = await BrowserFaviconRenderLoader.decode(request),
            !Task.isCancelled
        else { return }
        renderState.publish(
            Image(
                decorative: image,
                scale: TabFaviconMetrics.renderedImageScale
            ),
            for: request.identity,
            isCancelled: Task.isCancelled
        )
    }
}

/// A tab of the read model's icon: the row reads its own tab's fields and
/// image slot, so a new icon redraws only this tab's icon.
struct TabStateFaviconView: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    var body: some View {
        TabFaviconView(
            subject: BrowserTabFaviconSubject(tab: tab, image: favicons.icon(of: tab.id)), profileID: profileID,
            size: size)
    }
}
