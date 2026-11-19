import SwiftUI

struct BrowserNowPlaying: View {
    let page: BrowserPage
    let selectTab: () -> Void

    private var title: String { page.mediaTitle.isEmpty ? page.title : page.mediaTitle }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: selectTab) {
                HStack(spacing: 8) {
                    if let data = page.favicon, let icon = NSImage(data: data) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 28)
                    } else {
                        Image(systemName: "music.note").frame(width: 28)
                    }
                    Text(title).lineLimit(1)
                }
                .padding(.leading, 9).padding(.trailing, 4)
                .frame(maxWidth: .infinity, minHeight: SidebarGeometry.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show tab playing \(title)")
            if page.mediaActions.contains("previoustrack") {
                mediaButton("previoustrack", symbol: "backward.fill", label: "Previous Track")
            }
            mediaButton(
                page.isPlaying ? "pause" : "play", symbol: page.isPlaying ? "pause.fill" : "play.fill",
                label: page.isPlaying ? "Pause" : "Play")
            if page.mediaActions.contains("nexttrack") {
                mediaButton("nexttrack", symbol: "forward.fill", label: "Next Track")
            }
        }
        .padding(.trailing, 6)
        .browserHoverSurface(cornerRadius: SidebarGeometry.panelRadius)
        .browserSidebarPanel()
        .accessibilityElement(children: .contain).accessibilityLabel("Now Playing")
        .contextMenu {
            Button(page.mediaIsMuted ? "Unmute" : "Mute") {
                page.performMediaAction(page.mediaIsMuted ? "unmute" : "mute")
            }
            Button("Hide Now Playing") { page.nowPlayingHidden = true }
        }
    }

    private func mediaButton(_ action: String, symbol: String, label: String) -> some View {
        Button {
            page.performMediaAction(action)
        } label: {
            Image(systemName: symbol).font(.system(size: 12))
        }
        .buttonStyle(BrowserChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
        .accessibilityLabel(label)
    }
}
