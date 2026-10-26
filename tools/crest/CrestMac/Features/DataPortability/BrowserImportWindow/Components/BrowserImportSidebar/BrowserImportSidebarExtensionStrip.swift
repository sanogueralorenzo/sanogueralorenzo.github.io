import AppKit
import SwiftUI

/// The extensions a preview sidebar shows under its address field, where
/// Crest keeps a Space's pinned extensions. Given `setIncluded`, each tile
/// turns its extension on or off, the way a tab does; without it the row only
/// shows what the import brings.
struct BrowserImportSidebarExtensionStrip: View {
    // MARK: - Static Variables

    private static let tileSize: CGFloat = 30
    private static let glyphSize: CGFloat = 20
    private static let spacing: CGFloat = 4

    // MARK: - Variables

    let extensions: [ImportExtension]
    let icons: [String: NSImage]
    var includedIDs: Set<String>?
    var setIncluded: ((String, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXTENSIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)
                .accessibilityHidden(true)

            tiles
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 9, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Extensions")
    }

    private var tiles: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            ForEach(extensions, id: \.extensionID) { item in
                if let setIncluded {
                    let included = isIncluded(item)
                    Button {
                        setIncluded(item.extensionID, !included)
                    } label: {
                        tile(item, included: included)
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                    .accessibilityLabel(item.name)
                    .accessibilityValue(included ? "Included" : "Not included")
                } else {
                    tile(item, included: true)
                        .help(item.name)
                        .accessibilityElement()
                        .accessibilityLabel(item.name)
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.tileSize, maximum: Self.tileSize), spacing: Self.spacing)]
    }

    // MARK: - Actions - Drawing

    private func isIncluded(_ item: ImportExtension) -> Bool {
        includedIDs?.contains(item.extensionID) ?? true
    }

    private func tile(_ item: ImportExtension, included: Bool) -> some View {
        icon(item)
            .frame(width: Self.glyphSize, height: Self.glyphSize)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .saturation(included ? 1 : 0)
            .opacity(included ? 1 : 0.38)
            .overlay(alignment: .topTrailing) {
                if !included {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(.rect)
    }

    @ViewBuilder
    private func icon(_ item: ImportExtension) -> some View {
        if let image = icons[item.extensionID] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}
