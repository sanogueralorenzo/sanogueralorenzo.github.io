import SwiftUI

/// Device-wide routing choices, including choices made through a page's menu.
/// Changing a choice affects future pages and navigations, leaving open pages
/// on their current engine until the person chooses to move them.
struct BrowserEngineSettingsPane: View {
    // MARK: - Variables

    let core: CrestCore
    @State private var editing: BrowserEngineRuleDraft?
    @State private var failure: String?

    private var preferences: EnginePreferences { core.state.enginePreferences }
    private var availableEngines: [EngineKind] { core.state.engines?.engines.map(\.kind) ?? [] }
    private var defaultEngine: EngineKind {
        core.state.engines?.engines.first(where: \.isDefault)?.kind ?? BrowserEngineRegistration.current.kind
    }

    // MARK: - Actions - Presentation

    var body: some View {
        BrowserSettingsPane(.engines) {
            Section {
                ForEach(BrowserEngineOption.all) { option in
                    BrowserEngineOptionCard(
                        option: option, isSelected: defaultEngine == option.engine,
                        isRecommended: BrowserEngineRegistration.current.kind == option.engine,
                        isAvailable: availableEngines.contains(option.engine)
                    ) { selectDefault(option.engine) }
                }
                if preferences.defaultEngine != nil {
                    HStack {
                        Spacer()
                        Button("Use Recommended") { selectDefault(nil) }
                    }
                }
            } header: {
                Text("Default engine")
            } footer: {
                CrestFormFootnote("Open pages keep their engine.")
            }
            Section {
                if preferences.rules.isEmpty {
                    Text("No website rules")
                        .foregroundStyle(.secondary)
                }
                ForEach(preferences.rules.sorted { $0.origin.displayName < $1.origin.displayName }, id: \.origin) {
                    rule in
                    HStack {
                        Button {
                            editing = BrowserEngineRuleDraft(rule: rule)
                        } label: {
                            HStack {
                                Text(rule.origin.displayName)
                                Spacer()
                                Text(rule.engine.title).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(rule.origin.displayName), \(String(localized: rule.engine.title))")
                        Button("Remove Rule", systemImage: "minus.circle") { remove(rule) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Return this website to the default engine")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Website Rule…") {
                        editing = BrowserEngineRuleDraft(engine: defaultEngine)
                    }
                    .accessibilityIdentifier("add-engine-rule")
                }
            } header: {
                Text("Website rules")
            } footer: {
                CrestFormFootnote("A rule for a site doesn’t include its subdomains.")
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { draft in
            BrowserEngineRuleEditor(core: core, draft: draft, availableEngines: availableEngines)
        }
    }

    // MARK: - Actions - Preferences

    private func selectDefault(_ engine: EngineKind?) {
        do {
            try core.send(SelectDefaultEngine(engine: engine))
            failure = nil
        } catch { failure = error.explanation }
    }

    private func remove(_ rule: SiteEngineRule) {
        do {
            try core.send(ForgetEngineRule(origin: rule.origin))
            failure = nil
        } catch { failure = error.explanation }
    }
}
