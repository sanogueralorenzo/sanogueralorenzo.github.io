import SwiftUI

/// Where each kind of Crest content lives, as plain status rows.
struct BrowserSyncContentScopeSection: View {
    var body: some View {
        Section("What syncs") {
            LabeledContent("Spaces, tabs and history", value: String(localized: "iCloud"))
            LabeledContent("Crest Passwords", value: String(localized: "iCloud Keychain, per Space"))
            LabeledContent("Cookies and website data", value: String(localized: "This device only"))
        }
    }
}
