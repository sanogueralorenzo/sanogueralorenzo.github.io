import SwiftUI

struct BrowserEngineRuleEditor: View {
    // MARK: - Variables

    let core: CrestCore
    let availableEngines: [EngineKind]
    @State private var draft: BrowserEngineRuleDraft
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var websiteFocused: Bool

    private var origin: SiteOrigin? {
        let text = draft.website.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: address), let scheme = url.scheme,
            WebScheme.named(scheme.lowercased()) != nil,
            url.user == nil, url.password == nil, let host = url.host(),
            !host.isEmpty, !host.contains(where: \.isWhitespace)
        else { return nil }
        return SiteOrigin(url: url)
    }

    // MARK: - Initializers

    init(core: CrestCore, draft: BrowserEngineRuleDraft, availableEngines: [EngineKind]) {
        self.core = core
        self.availableEngines = availableEngines
        _draft = State(initialValue: draft)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text(draft.previousOrigin == nil ? "Add Website Rule" : "Edit Website Rule")
                .font(.headline)
            Form {
                TextField("Website", text: $draft.website, prompt: Text("https://example.com"))
                    .focused($websiteFocused)
                    .accessibilityIdentifier("engine-rule-website")
                Picker("Engine", selection: $draft.engine) {
                    ForEach(EngineKind.all, id: \.self) { engine in
                        Text(engine.title).tag(engine).disabled(!availableEngines.contains(engine))
                    }
                }
                .accessibilityIdentifier("engine-rule-engine")
                if let origin {
                    Text("Applies to \(origin.displayName)").foregroundStyle(.secondary)
                } else {
                    Text("Enter an HTTP or HTTPS website.").foregroundStyle(.secondary)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(origin == nil || !availableEngines.contains(draft.engine))
                    .accessibilityIdentifier("save-engine-rule")
            }
        }
        .padding(CrestSpacing.large)
        .frame(width: 420)
        .onAppear { websiteFocused = true }
    }

    // MARK: - Actions - Save

    private func save() {
        guard let origin else { return }
        do {
            try core.send(EditEngineRule(previousOrigin: draft.previousOrigin, origin: origin, engine: draft.engine))
            dismiss()
        } catch { failure = error.explanation }
    }
}
