import SwiftUI

struct BrowserAdditionalSettings: View {
    let store: BrowserStore
    let selection: BrowserSettingsSelection

    var body: some View {
        BrowserSettingsForm {
            switch selection {
            case .engines:
                Section {
                    Label("Chromium", systemImage: "circle").foregroundStyle(.secondary)
                    Text("Unavailable in this build").font(.caption).foregroundStyle(.secondary)
                    Label("WebKit", systemImage: "checkmark.circle.fill")
                    Text("Recommended · Native macOS handling, FairPlay protected video, Reader Mode").font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Default engine")
                } footer: {
                    Text("Open pages keep their engine.")
                }
            case .sync:
                Section("iCloud") {
                    Toggle("Sync with iCloud", isOn: .constant(false)).disabled(true)
                    LabeledContent("Status", value: "Unavailable in this build")
                    Text("iCloud sync requires a build signed for Lean’s iCloud container.").foregroundStyle(.secondary)
                    Button("Sync Now") {}.disabled(true)
                    Button("Pull from iCloud…") {}.disabled(true)
                }
            case .agents:
                Section {
                    Toggle("Allow agents to use Lean", isOn: .constant(false)).disabled(true)
                    Text("Agent connections are unavailable in this build.").foregroundStyle(.secondary)
                }
                Section("Spaces") {
                    ForEach(store.session.spaces) { space in Toggle(space.name, isOn: .constant(false)).disabled(true) }
                    Toggle("Let agents run scripts in pages", isOn: .constant(false)).disabled(true)
                }
                Section("Allowed agents") { Text("No agents yet").foregroundStyle(.secondary) }
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
                        "Lean",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("A native macOS browser").foregroundStyle(.secondary)
                    Link(
                        "GitHub",
                        destination: URL(
                            string:
                                "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/tools/browser"
                        )!)
                }
            default: EmptyView()
            }
        }
    }
}
