import SwiftUI

struct BrowserExtensionInstallSpacesPage: View {
    let primarySpaceName: String
    let spaces: [BrowserSpaceIdentity]
    @Binding var selection: Set<UUID>
    let goBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            Button("Back", systemImage: "chevron.left", action: goBack)
            Text("Install in Other Spaces")
                .font(.title2.bold())
            Text("This extension will be installed in \(primarySpaceName). Select any additional Spaces below.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Each Space gets an independent copy with the permissions you choose. Extension data stays separate.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            BrowserExtensionSpaceSelectionList(spaces: spaces, selection: $selection)
        }
    }
}
