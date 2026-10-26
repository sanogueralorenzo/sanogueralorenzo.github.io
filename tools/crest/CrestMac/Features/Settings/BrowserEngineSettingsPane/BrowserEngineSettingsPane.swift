import SwiftUI

/// The global engine choice.
/// Changing a choice affects future pages, leaving open pages
/// on their current engine until the person chooses to move them.
struct BrowserEngineSettingsPane: View {
    // MARK: - Variables

    let core: CrestCore
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
            if let failure { Text(failure).foregroundStyle(.red) }
        }
    }

    // MARK: - Actions - Preferences

    private func selectDefault(_ engine: EngineKind?) {
        do {
            try core.send(SelectDefaultEngine(engine: engine))
            failure = nil
        } catch { failure = error.explanation }
    }

}
