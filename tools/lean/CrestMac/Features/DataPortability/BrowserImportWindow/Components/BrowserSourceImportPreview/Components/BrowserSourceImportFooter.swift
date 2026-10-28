import SwiftUI

struct BrowserSourceImportFooter: View {
    var body: some View {
        ZStack {
            HStack {
                if let symbol = BrowserImportPreviewControls.sourceFooterLeadingSymbol {
                    Image(systemName: symbol)
                }
                Spacer()
                Image(systemName: "plus")
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(.primary.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.ultraThinMaterial)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSourceImportFooter().padding().frame(width: 360)
    }
#endif
