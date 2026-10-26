import SwiftUI

struct BrowserTranslationSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared
    @State private var catalog = BrowserTranslationLanguageCatalog()
    @State private var couldNotOpenLanguages = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var rules: [TranslationRule] { preferences.preferences.translationRules }
    private var automaticallyTranslates: Bool { preferences.automaticallyTranslates }
    private var sourceIDs: [String] {
        let installed = catalog.installedIDs
        let saved = rules.map(\.sourceLanguage).filter { saved in
            !BrowserTranslationLanguageCatalog.matches(saved, in: installed).contains(true)
        }
        return (installed + saved).sorted {
            BrowserTranslationLanguageCatalog.name($0).localizedStandardCompare(
                BrowserTranslationLanguageCatalog.name($1)) == .orderedAscending
        }
    }

    var body: some View {
        Section("Translation") {
            Toggle("Offer to translate pages", isOn: $preferences.offersTranslation)
            Toggle("Translate automatically", isOn: $preferences.automaticallyTranslates)
                .accessibilityIdentifier("automatic-translation-toggle")
        }
        if automaticallyTranslates {
            languagesSection
        }
    }

    private var languagesSection: some View {
        Section {
            if !sourceIDs.isEmpty {
                ForEach(sourceIDs, id: \.self) { source in
                    languageRow(source)
                }
            } else if catalog.hasChecked {
                Text("No downloaded languages")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) { languageActions }
        } header: {
            Text("Translate automatically from")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                #if os(macOS)
                    CrestFormFootnote("Add languages in System Settings › General › Language & Region.")
                #else
                    CrestFormFootnote("Download languages in the Translate app.")
                #endif
                if couldNotOpenLanguages {
                    Text("Couldn’t open language downloads.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .task { await catalog.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await catalog.refresh() } }
        }
    }

    @ViewBuilder
    private var languageActions: some View {
        Button {
            Task { await catalog.refresh() }
        } label: {
            Text(catalog.isRefreshing ? "Checking…" : "Refresh")
        }
        .disabled(catalog.isRefreshing)
        .accessibilityIdentifier("refresh-translation-languages")
        #if os(macOS)
            Button("Download Languages…") {
                openLanguages(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
            }
        #else
            Button("Open Translate…") {
                openLanguages(URL(string: "translate://")!)
            }
        #endif
    }

    /// The system answers whether it opened `url` on a queue of its own, so
    /// the answer comes back to the main actor before it reaches the view.
    private func openLanguages(_ url: URL) {
        openURL(url) { @Sendable accepted in
            Task { @MainActor in couldNotOpenLanguages = !accepted }
        }
    }

    private func languageRow(_ source: String) -> some View {
        let targets = catalog.targets(for: source)
        let saved = rules.decision(for: source)?.rule
        let preferred = Locale.preferredLanguages.first ?? "en"
        let target =
            saved?.targetID
            ?? zip(targets, BrowserTranslationLanguageCatalog.matches(preferred, in: targets)).first { $0.1 }?.0 ?? ""
        let enabled = saved?.isEnabled ?? false
        let available = targets.contains(target)
        return LabeledContent {
            HStack(spacing: 12) {
                destinationPicker(source, target: target, targets: targets, enabled: enabled)
                    .labelsHidden()
                    .fixedSize()
                languageToggle(source, target: target, enabled: enabled, available: available)
                    .labelsHidden()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(BrowserTranslationLanguageCatalog.name(source))
                if !target.isEmpty && !available && catalog.hasChecked {
                    Text("Download both languages to translate")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!automaticallyTranslates)
    }

    private func languageToggle(_ source: String, target: String, enabled: Bool, available: Bool) -> some View {
        Toggle(
            isOn: Binding(
                get: { enabled },
                set: { save(source, target: target, enabled: $0) }
            )
        ) {
            Text(BrowserTranslationLanguageCatalog.name(source))
        }
        .toggleStyle(.switch)
        .disabled(!enabled && !available)
        .accessibilityIdentifier("automatic-translation-source-\(source)")
    }

    private func destinationPicker(_ source: String, target: String, targets: [String], enabled: Bool) -> some View {
        Picker(
            "Translate to",
            selection: Binding(
                get: { target }, set: { save(source, target: $0, enabled: enabled) }
            )
        ) {
            if target.isEmpty { Text("Choose Language").tag("") }
            if !target.isEmpty && !targets.contains(target) {
                Text("\(BrowserTranslationLanguageCatalog.name(target)) — Not Downloaded").tag(target)
            }
            ForEach(targets, id: \.self) { id in
                Text(BrowserTranslationLanguageCatalog.name(id)).tag(id)
            }
        }
        .pickerStyle(.menu)
        .disabled(targets.isEmpty)
        .accessibilityLabel("Translate \(BrowserTranslationLanguageCatalog.name(source)) to")
    }

    private func save(_ source: String, target: String, enabled: Bool) {
        preferences.setTranslationRule(sourceID: source, targetID: target, isEnabled: enabled)
    }
}
