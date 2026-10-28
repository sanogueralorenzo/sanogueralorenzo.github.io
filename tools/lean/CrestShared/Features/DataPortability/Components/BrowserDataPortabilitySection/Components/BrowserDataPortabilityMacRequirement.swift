import SwiftUI

struct BrowserDataPortabilityMacRequirement: View {
    var body: some View {
        Text("Importing from another browser needs Crest for Mac. Imported Spaces sync here with iCloud.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("browser-import-macos-requirement")
    }
}
