import SwiftUI

struct BrowserCrestImportChrome: View {
    let space: SpaceModel
    let highlightedTabID: UUID?

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                    .opacity(0.45)
                Spacer()
                Image(systemName: "sidebar.left")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                Text(selectedHost ?? "Search or enter website")
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(.thinMaterial, in: .rect(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var selectedHost: String? {
        highlightedTabID.flatMap { id in
            space.tabs.model(id)?.address?.host
        }
    }
}
