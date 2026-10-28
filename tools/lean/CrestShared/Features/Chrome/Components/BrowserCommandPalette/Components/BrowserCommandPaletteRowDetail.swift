import SwiftUI

/// The row's subtitle, below its title.
struct BrowserCommandPaletteRowDetail: View {
    // MARK: - Variables

    let row: PaletteRow

    var body: some View {
        if !row.subtitle.isEmpty {
            Text(verbatim: row.subtitle)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
