import SwiftUI

struct BrowserPeekCloseButton: View {
    let accessibilityLabel: LocalizedStringKey
    let help: LocalizedStringKey
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label("Close", systemImage: "xmark")
                .frame(maxWidth: .infinity)
                .frame(height: BrowserPeekActionBar.controlHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .keyboardShortcut("w", modifiers: .command)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier("peek-close-control")
        .help(Text(help))
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserPeekCloseButton(accessibilityLabel: "Close Peek", help: "Close Peek", dismiss: {}).padding()
    }
#endif
