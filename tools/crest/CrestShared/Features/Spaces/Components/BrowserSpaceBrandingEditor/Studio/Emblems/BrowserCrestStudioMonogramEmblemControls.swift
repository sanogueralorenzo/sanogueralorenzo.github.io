import SwiftUI

/// Edits a monogram emblem's letters and their style.
struct BrowserCrestStudioMonogramEmblemControls: View {
    @Binding var monogram: String
    @Binding var monogramStyle: CrestMonogramStyle

    var body: some View {
        BrowserCrestStudioTextField(title: "One or two letters", text: $monogram)
        Picker("Letter style", selection: $monogramStyle) {
            Text("Serif").tag(CrestMonogramStyle.serif)
            Text("Sans").tag(CrestMonogramStyle.sans)
        }.pickerStyle(.segmented)
    }
}
