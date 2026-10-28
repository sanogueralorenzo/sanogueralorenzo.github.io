import SwiftUI

struct BrowserNavigationFailureDetailRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureDetailRow(label: "Address", value: "https://example.com/a/long/path/to/a/page")
            .padding().frame(width: 360)
    }
#endif
