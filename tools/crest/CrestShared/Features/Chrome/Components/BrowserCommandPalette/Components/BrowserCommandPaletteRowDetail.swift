import SwiftUI

/// A row's second line: its subtitle and, when the person asked to see why
/// results appear, the reason the palette ranked it there.
struct BrowserCommandPaletteRowDetail: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow

    var body: some View {
        let reason = model.preferences.showsReasons ? row.reason : nil
        if !row.subtitle.isEmpty || reason != nil {
            HStack(spacing: CrestSpacing.extraSmall) {
                if !row.subtitle.isEmpty {
                    Text(verbatim: row.subtitle)
                        .lineLimit(1)
                }
                if let reason {
                    if !row.subtitle.isEmpty { Text(verbatim: "·") }
                    Text(reason.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
