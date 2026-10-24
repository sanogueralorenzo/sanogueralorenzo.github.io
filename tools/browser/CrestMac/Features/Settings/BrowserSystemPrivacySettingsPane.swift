import SwiftUI

/// What macOS lets Crest reach, and the way into each Space's own privacy.
struct BrowserSystemPrivacySettingsPane: View {
    @Environment(\.browserSettingsOpenSpace) private var openSpace
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    var body: some View {
        BrowserSettingsPane(.privacy) {
            BrowserSystemPermissionSettingsSection(browser: browser, spaceAccess: spaceAccess)

            if let openSpace {
                Section {
                    ForEach(browser.spaceModels) { space in
                        Button {
                            openSpace(space.id, tab: .privacy)
                        } label: {
                            LabeledContent {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            } label: {
                                Label {
                                    Text(space.settings.name)
                                } icon: {
                                    BrowserSpaceIdentityIcon(space: space, size: 18)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-space-privacy-\(space.id)")
                    }
                } header: {
                    Text("Spaces")
                } footer: {
                    CrestFormFootnote("Each Space keeps its own history, site permissions and blocking.")
                }
            }
        }
    }
}

/// Opens one page of a Space's settings from anywhere inside Settings.
struct BrowserSettingsOpenSpaceAction {
    let open: @MainActor (UUID, BrowserSpaceSettingsTab?, BrowserSettingsSpaceIntent) -> Void

    /// Shows `tab` of the Space, or the page it last showed when nil.
    @MainActor
    func callAsFunction(
        _ id: UUID, tab: BrowserSpaceSettingsTab? = nil, intent: BrowserSettingsSpaceIntent = .none
    ) {
        open(id, tab, intent)
    }
}

private struct BrowserSettingsOpenSpaceKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsOpenSpaceAction? = nil
}

extension EnvironmentValues {
    var browserSettingsOpenSpace: BrowserSettingsOpenSpaceAction? {
        get { self[BrowserSettingsOpenSpaceKey.self] }
        set { self[BrowserSettingsOpenSpaceKey.self] = newValue }
    }
}
