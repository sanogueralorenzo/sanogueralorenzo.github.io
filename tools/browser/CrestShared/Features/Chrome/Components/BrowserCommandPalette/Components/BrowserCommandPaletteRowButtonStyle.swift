import SwiftUI

struct BrowserCommandPaletteRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, BrowserCommandPaletteMetrics.rowHorizontalPadding)
            .frame(minHeight: BrowserCommandPaletteMetrics.resultRowHeight)
            .contentShape(.rect)
            .background(
                isSelected
                    ? Color.accentColor.opacity(
                        BrowserCommandPaletteMetrics.selectedRowOpacity
                    )
                    : Color.primary.opacity(
                        BrowserCommandPaletteMetrics.restingRowOpacity
                    ),
                in: .rect(cornerRadius: BrowserCommandPaletteMetrics.rowCornerRadius)
            )
    }
}
