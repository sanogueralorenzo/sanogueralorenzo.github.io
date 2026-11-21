import SwiftUI

struct BrowserAboutSettings: View {
    var body: some View {
        BrowserSettingsForm {
            Section {
                LabeledContent(
                    "Browser",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text("A native macOS browser").foregroundStyle(.secondary)
                Link("itsbrowser.com", destination: URL(string: "https://itsbrowser.com")!)
                Link(
                    "GitHub",
                    destination: URL(
                        string: "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/browser"
                    )!)
            }
        }
    }
}
