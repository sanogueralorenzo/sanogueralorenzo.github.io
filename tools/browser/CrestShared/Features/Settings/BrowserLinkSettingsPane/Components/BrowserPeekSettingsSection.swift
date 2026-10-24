import SwiftUI

struct BrowserPeekSettingsSection: View {
    @Binding var automaticallyOpensPeek: Bool
    @Binding var clickModifier: LinkPeekModifier
    /// Absent where links can't be dragged out of a page.
    var dragsLinksToPeek: Binding<Bool>? = nil

    var body: some View {
        Section {
            Toggle(
                "Open cross-site links from pinned and saved tabs in Peek",
                isOn: $automaticallyOpensPeek
            )
            .accessibilityIdentifier("automatic-peek")

            Picker("Open Peek with", selection: $clickModifier) {
                ForEach(LinkPeekModifier.all, id: \.self) { modifier in
                    Text(modifier.title).tag(modifier)
                }
            }
            .accessibilityIdentifier("peek-click-modifier")

            if let dragsLinksToPeek {
                Toggle("Drag links to Peek", isOn: dragsLinksToPeek)
                    .accessibilityIdentifier("drag-links-to-peek-toggle")
            }
        } header: {
            Text("Peek")
        } footer: {
            CrestFormFootnote(
                dragsLinksToPeek == nil
                    ? "The other key opens the link in a new tab."
                    : "The other key opens a new tab. Hold Option to drag the link itself."
            )
        }
    }
}
