import AppKit
import SwiftUI
import WebKit

struct BrowserSiteSettings: View {
    let store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    private var origin: String? { store.activePage?.url.flatMap(BrowserStore.siteOrigin) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Website Settings").font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            if let origin {
                Text(origin).font(.callout).foregroundStyle(.secondary)
                Form {
                    ForEach(BrowserSitePermission.Kind.allCases) { kind in
                        Picker(
                            kind.label,
                            selection: Binding(
                                get: { store.permission(kind, origin: origin, spaceID: store.activeSpace.id) },
                                set: {
                                    store.setPermission(
                                        kind, origin: origin, spaceID: store.activeSpace.id, decision: $0)
                                })
                        ) {
                            ForEach(BrowserSitePermission.Decision.allCases, id: \.self) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                    }
                    Button("Clear This Site's Data", role: .destructive) { clear(origin) }
                }.formStyle(.grouped)
            } else {
                Text("Open a website to manage its permissions.").foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 420)
    }
    private func clear(_ origin: String) {
        guard let host = URL(string: origin)?.host else { return }
        let profile = store.profile(for: store.activeSpace.id)
        profile.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let matches = records.filter { $0.displayName == host || host.hasSuffix("." + $0.displayName) }
            profile.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matches) {
                Task { @MainActor in store.showNotice("Website data cleared") }
            }
        }
    }
}
