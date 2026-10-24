import SwiftUI

/// Empties the address without leaving the edit in progress.
struct BrowserSidebarAddressClearButton: View {
    @Binding var text: String
    /// The shell's own sizing. Absent where the control inherits the field's
    /// font rather than naming one — passing `nil` to `font(_:)` would reset it
    /// to the system default instead of leaving it alone.
    var font: Font?

    @ViewBuilder
    var body: some View {
        if let font {
            control.font(font)
        } else {
            control
        }
    }

    private var control: some View {
        Button("Clear", systemImage: "xmark.circle.fill") {
            text = ""
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
    }
}

#if DEBUG
    #Preview("Clear address") {
        @Previewable @State var text = "crestbrowser.com"
        HStack {
            TextField("Address", text: $text)
            BrowserSidebarAddressClearButton(text: $text)
        }.padding().frame(width: 320)
    }
#endif
