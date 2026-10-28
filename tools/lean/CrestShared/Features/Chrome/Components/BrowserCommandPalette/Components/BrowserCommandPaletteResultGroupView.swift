import SwiftUI

struct BrowserCommandPaletteResultGroupView: View {
    let model: BrowserCommandPaletteModel
    let group: BrowserCommandPaletteGroup

    @ViewBuilder
    var body: some View {
        if let header = group.section.title {
            VStack(
                alignment: .leading,
                spacing: BrowserCommandPaletteMetrics.resultHeaderSpacing
            ) {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(
                        .horizontal,
                        BrowserCommandPaletteMetrics.resultHeaderHorizontalPadding
                    )
                BrowserCommandPaletteResultRows(model: model, group: group)
            }
        } else {
            BrowserCommandPaletteResultRows(model: model, group: group)
        }
    }
}
