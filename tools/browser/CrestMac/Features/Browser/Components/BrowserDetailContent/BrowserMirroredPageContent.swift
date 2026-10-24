import SwiftUI

struct BrowserMirroredPageContent: View {
    let tabID: UUID
    let pages: BrowserPagePool

    var body: some View {
        ZStack {
            if let snapshot = pages.mirroredPageSnapshot(for: tabID) {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 12)
                    .accessibilityHidden(true)
            }
            Rectangle().fill(.ultraThinMaterial)
            Button {
                pages.claimPresentedPage(for: tabID)
            } label: {
                Label("Active in another window", systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                    .padding(20)
                    .background { CrestSurfaceLayer(shape: .rect(cornerRadius: 12)) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Move this page here without reloading it.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { pages.claimPresentedPage(for: tabID) }
    }
}
