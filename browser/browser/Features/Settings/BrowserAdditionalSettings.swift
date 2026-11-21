import SwiftUI

struct BrowserAdditionalSettings: View {
    let store: BrowserStore
    let selection: BrowserSettingsSelection

    var body: some View {
        BrowserSettingsForm {
            switch selection {
            case .advanced:
                Section("Import") { Button("Import from Another Browser…") { store.importBrowserData() } }
                Section {
                    Button("Export Browser Data…") { store.saveExport(bookmarks: false) }
                    Button("Import Browser Data…") { store.importBrowserData() }
                    Button("Export Bookmarks as HTML…") { store.saveExport(bookmarks: true) }
                } header: {
                    Text("Import and export")
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
