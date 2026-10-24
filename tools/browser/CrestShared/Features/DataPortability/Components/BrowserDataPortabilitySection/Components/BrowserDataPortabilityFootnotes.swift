import SwiftUI

struct BrowserDataPortabilityFootnotes: View {
    var body: some View {
        Text("Exports never include passwords, cookies, website data or extensions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("browser-data-exclusions")
    }
}
