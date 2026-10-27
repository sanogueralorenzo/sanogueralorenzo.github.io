import SwiftUI
@preconcurrency import Translation

struct BrowserGeneralSettings: View {
    let store: BrowserStore
    @State private var languages = ["en"]
    @State private var isDefault = false

    private var zoomLevels: [Double] {
        let saved = store.preferences.defaultPageZoom ?? 1
        return BrowserPageZoom.levels.contains(where: { abs($0 - saved) < 0.001 })
            ? BrowserPageZoom.levels : (BrowserPageZoom.levels + [saved]).sorted()
    }

    var body: some View {
        BrowserSettingsForm {
            Section {
                LabeledContent {
                    Picker(
                        "Default page zoom",
                        selection: Binding(
                            get: { store.preferences.defaultPageZoom ?? 1 },
                            set: { store.setDefaultPageZoom($0) }
                        )
                    ) {
                        ForEach(zoomLevels, id: \.self) { value in
                            Text("\(Int((value * 100).rounded()))%").tag(value)
                        }
                    }.labelsHidden().fixedSize().accessibilityLabel("Default page zoom").accessibilityIdentifier(
                        "default-page-zoom-slider")
                } label: {
                    HStack(spacing: 4) {
                        Text("Default page zoom")
                        Button {
                            store.setDefaultPageZoom(1)
                        } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                                .frame(width: 18, height: 18).background(.quaternary, in: Circle()).frame(
                                    width: 28, height: 28)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .opacity((store.preferences.defaultPageZoom ?? 1) == 1 ? 0 : 1)
                        .allowsHitTesting((store.preferences.defaultPageZoom ?? 1) != 1)
                        .accessibilityHidden((store.preferences.defaultPageZoom ?? 1) == 1)
                        .accessibilityLabel("Reset Default page zoom to default")
                    }
                }
            } header: {
                HStack {
                    Text("Page")
                    Spacer()
                    Button("Reset") { store.setDefaultPageZoom(1) }.buttonStyle(.borderless).controlSize(.small)
                        .opacity((store.preferences.defaultPageZoom ?? 1) == 1 ? 0 : 1)
                        .disabled((store.preferences.defaultPageZoom ?? 1) == 1)
                        .accessibilityHidden((store.preferences.defaultPageZoom ?? 1) == 1)
                }
            }
            Section {
                LabeledContent("Default browser") {
                    HStack(spacing: 8) {
                        Label(
                            isDefault ? "Default browser" : "Another browser",
                            systemImage: isDefault ? "checkmark.circle" : "circle"
                        )
                        .foregroundStyle(.secondary)
                        if !isDefault {
                            Button("Make Default") {
                                Task {
                                    do {
                                        for scheme in ["http", "https"] {
                                            try await NSWorkspace.shared.setDefaultApplication(
                                                at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
                                        }
                                        checkDefault()
                                    } catch { store.showNotice(error.localizedDescription) }
                                }
                            }
                        }
                        Button("Check Again", systemImage: "arrow.clockwise") { checkDefault() }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
            }
            Section("Search") {
                Picker("Search provider", selection: preference(\.searchProvider)) {
                    ForEach(SearchProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Search suggestions", isOn: preference(\.searchSuggestions))
            }
            Section("Translate") {
                Toggle("Translate Automatically", isOn: preference(\.translatesAutomatically))
                Picker("Translate Language", selection: preference(\.translationLanguage)) {
                    ForEach(languages, id: \.self) { Text(languageName($0)).tag($0) }
                }
                LabeledContent("Excluded Languages") {
                    Menu(
                        store.preferences.excludedLanguages.isEmpty
                            ? "None"
                            : store.preferences.excludedLanguages.sorted().map(languageName).joined(separator: ", ")
                    ) {
                        ForEach(
                            Array(Set(languages.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 }))
                                .sorted(), id: \.self
                        ) { code in
                            Toggle(
                                languageName(code),
                                isOn: Binding(
                                    get: { store.preferences.excludedLanguages.contains(code) },
                                    set: { excluded in
                                        store.updatePreferences {
                                            if excluded {
                                                $0.excludedLanguages.insert(code)
                                            } else {
                                                $0.excludedLanguages.remove(code)
                                            }
                                        }
                                    }
                                ))
                        }
                    }
                }
            }
        }
        .task {
            checkDefault()
            let supported = await LanguageAvailability().supportedLanguages
            languages = Array(Set(supported.map(\.minimalIdentifier) + [store.preferences.translationLanguage]))
                .sorted { languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending }
        }
    }

    private func checkDefault() {
        isDefault = ["http", "https"].allSatisfy {
            NSWorkspace.shared.urlForApplication(toOpen: URL(string: $0 + "://example.com")!)?.standardizedFileURL
                == Bundle.main.bundleURL.standardizedFileURL
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<BrowserPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private func languageName(_ code: String) -> String { Locale.current.localizedString(forIdentifier: code) ?? code }
}
