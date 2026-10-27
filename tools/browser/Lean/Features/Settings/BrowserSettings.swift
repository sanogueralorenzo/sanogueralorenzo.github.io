import AVFoundation
import AuthenticationServices
import SwiftUI
@preconcurrency import Translation
import UserNotifications
import WebKit

struct BrowserSettings: View {
    let store: BrowserStore
    @State private var accessRevision = 0
    @State private var languages = ["en"]
    @State private var showsWebKitFeatures = false

    var body: some View {
        if showsWebKitFeatures {
            BrowserWebKitFeatureFlagSettings(store: store) { showsWebKitFeatures = false }
        } else {
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section("General") {
                Button("Make Default Browser") {
                    Task {
                        do {
                            for scheme in ["http", "https"] {
                                try await NSWorkspace.shared.setDefaultApplication(
                                    at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
                            }
                        } catch { store.showNotice(error.localizedDescription) }
                    }
                }
                Picker("Search Provider", selection: preference(\.searchProvider)) {
                    ForEach(SearchProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }
                }
                Toggle("Search Suggestions", isOn: preference(\.searchSuggestions))
            }
            Section("Translation") {
                Toggle("Translate Automatically", isOn: preference(\.translatesAutomatically))
                Picker("Translate Language", selection: preference(\.translationLanguage)) {
                    ForEach(languages, id: \.self) { code in Text(languageName(code)).tag(code) }
                }
                LabeledContent("Excluded Languages") {
                    Menu(
                        store.preferences.excludedLanguages.isEmpty
                            ? "None" : "\(store.preferences.excludedLanguages.count) selected"
                    ) {
                        ForEach(languages, id: \.self) { code in
                            Toggle(
                                languageName(code),
                                isOn: Binding(
                                    get: { store.preferences.excludedLanguages.contains(code) },
                                    set: { checked in
                                        store.updatePreferences {
                                            if checked {
                                                $0.excludedLanguages.insert(code)
                                            } else {
                                                $0.excludedLanguages.remove(code)
                                            }
                                        }
                                    }))
                        }
                    }
                }
            }
            Section("Privacy") {
                Toggle("Block Known Ads and Trackers", isOn: preference(\.blocksContent))
                Button("Clear History in This Space") { store.clearHistory() }
                Button("Clear Website Data in This Space", role: .destructive) {
                    let spaceID = store.activeSpace.id
                    store.profile(for: spaceID).removeData(
                        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
                    ) {
                        Task { @MainActor in store.showNotice("Website data cleared") }
                    }
                }
            }
            Section("Downloads") {
                Toggle("Ask Where to Save Each File", isOn: preference(\.downloadsAskEveryTime))
                Button("Download Folder for This Space…") { store.chooseDownloadDirectory() }
            }
            Section("Browser Data") {
                Button("Import Browser Data…") { store.importBrowserData() }
                Button("Export Browser Data…") { store.exportBrowserData() }
            }
            Section("System Access") {
                LabeledContent(
                    "Passkeys",
                    value: BrowserSystemAccess.passkeyCapability
                        ? BrowserSystemAccess.passkeyState : "Requires a signed browser entitlement")
                Button("Authorize Passkeys") {
                    Task {
                        await BrowserSystemAccess.requestPasskeys()
                        accessRevision += 1
                    }
                }.disabled(!BrowserSystemAccess.passkeyCapability)
                Button("Notification Settings") {
                    BrowserSystemAccess.settings("com.apple.Notifications-Settings.extension")
                }
                Button("Location Settings") {
                    BrowserSystemAccess.settings("com.apple.preference.security?Privacy_LocationServices")
                }
                Button("Camera Settings") {
                    BrowserSystemAccess.settings("com.apple.preference.security?Privacy_Camera")
                }
                Button("Microphone Settings") {
                    BrowserSystemAccess.settings("com.apple.preference.security?Privacy_Microphone")
                }
                Button("Screen Recording Settings") {
                    BrowserSystemAccess.settings("com.apple.preference.security?Privacy_ScreenCapture")
                }
            }.id(accessRevision)
            Section("Saved Website Permissions") {
                ForEach(store.activeSpace.permissions) { permission in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(permission.origin)
                            Text(permission.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(
                            permission.kind.label,
                            selection: Binding(
                                get: { permission.decision },
                                set: {
                                    store.setPermission(
                                        permission.kind, origin: permission.origin, spaceID: store.activeSpace.id,
                                        decision: $0)
                                })
                        ) {
                            ForEach(BrowserSitePermission.Decision.allCases, id: \.self) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }.labelsHidden()
                    }
                }
            }
            Section("Advanced") {
                Button("WebKit Feature Flags…") { showsWebKitFeatures = true }
            }
            Section("About") {
                LabeledContent(
                    "Lean",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text(store.activeSpace.isPrivate ? "WebKit · Private Space" : "WebKit · Local JSON session")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LeanBrandTheme.canvas)
        .task {
            let supported = await LanguageAvailability().supportedLanguages
            languages = Array(Set(supported.map(\.minimalIdentifier))).sorted { languageName($0) < languageName($1) }
            if !languages.contains(store.preferences.translationLanguage) {
                languages.append(store.preferences.translationLanguage)
            }
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<BrowserPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { value in
                store.updatePreferences { $0[keyPath: keyPath] = value }
            })
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
