import SwiftUI

struct BrowserDeveloperCustomViewportFields: View {
    @Binding var width: String
    @Binding var height: String
    let apply: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("Width", text: $width)
                .accessibilityLabel("Viewport Width")
                .accessibilityIdentifier("developer-viewport-width")
            Text("×")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Height", text: $height)
                .accessibilityLabel("Viewport Height")
                .accessibilityIdentifier("developer-viewport-height")
            BrowserDeveloperToolbarButton(
                label: "Apply Custom Viewport",
                systemImage: "checkmark",
                action: apply
            )
            .disabled(BrowserDeveloperViewport.customSize(width: width, height: height) == nil)
            .accessibilityIdentifier("developer-viewport-apply")
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(.callout, design: .monospaced))
        .frame(width: 160)
        .help("Width and height in CSS pixels, from 1 to 8192. Apply to resize the preview.")
    }
}
