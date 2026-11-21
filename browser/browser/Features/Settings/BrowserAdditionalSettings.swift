import SwiftUI

struct BrowserAdditionalSettings: View {
    let store: BrowserStore
    let selection: BrowserSettingsSelection

    var body: some View {
        BrowserSettingsForm {
            switch selection {
            case .advanced:
                Section {
                    Button("Export Browser Data…") { store.saveExport(bookmarks: false) }
                    Button("Export Bookmarks as HTML…") { store.saveExport(bookmarks: true) }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Exports never include passwords, cookies, website data or extensions.")
                }
            case .about:
                Section {
                    LabeledContent(
                        "Browser",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("A native macOS browser").foregroundStyle(.secondary)
                    Link("itsbrowser.com", destination: URL(string: "https://itsbrowser.com")!)
                    Link(
                        "GitHub",
                        destination: URL(
                            string:
                                "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/browser"
                        )!)
                }
            default: EmptyView()
            }
        }
    }
}
