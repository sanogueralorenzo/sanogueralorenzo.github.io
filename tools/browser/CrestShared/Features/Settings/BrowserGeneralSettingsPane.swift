import SwiftUI

/// Startup, browsing preferences, and the platform's default-browser actions.
struct BrowserGeneralSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true
    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared
    #if os(iOS)
        @AppStorage(
            MobileBrowserRootPreferences.allowsFloatingSidebarKey, store: BrowserChromeAppearancePreference.defaults)
        private var allowsFloatingSidebar = false
    #endif

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    var body: some View {
        BrowserSettingsPane(.general) {
            Section {
                // The Mac keeps the status and its action on one line; a
                // phone's row is too narrow, so the action takes a row of
                // its own there.
                #if os(macOS)
                    LabeledContent("Default browser") {
                        HStack(spacing: CrestSpacing.small) {
                            defaultBrowserStatus
                            defaultBrowserActions
                            checkAgainButton
                        }
                    }
                #else
                    HStack(spacing: CrestSpacing.small) {
                        Text("Default browser")
                        Spacer(minLength: CrestSpacing.small)
                        defaultBrowserStatus
                        checkAgainButton
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    defaultBrowserActions
                #endif
            } footer: {
                if let message = defaultBrowser.status.message {
                    Text(message).crestFormFootnote()
                }
            }

            Section("Startup") {
                #if os(macOS)
                    Picker("When Crest opens", selection: $appPreferences.startupBehavior) {
                        ForEach(StartupBehavior.settingsOrder, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                #else
                    Toggle("Start on new tab", isOn: startsOnNewTab)
                        .accessibilityIdentifier("start-on-new-tab")
                #endif

                CrestSpaceMenuPicker(
                    "Default Space",
                    selection: browser.defaultSpaceBinding(),
                    spaces: CrestSpaceIdentity.list(browser.spaceModels),
                    accessibilityIdentifier: "default-space-picker"
                )
            }

            #if os(iOS)
                Section("Sidebar") {
                    Toggle("Allow floating sidebar", isOn: $allowsFloatingSidebar)
                        .accessibilityIdentifier("allow-floating-sidebar")
                }
            #endif

            // Whole-page translation preferences, which reach only the pages of
            // an engine with page translation.
            if browser.core.state.offers(.translation) {
                BrowserTranslationSettingsSection()
            }

            #if os(macOS)
                Section {
                    BrowserSpellCheckingToggle()
                    BrowserPictureInPictureToggle()
                } header: {
                    Text("Webpages")
                } footer: {
                    CrestFormFootnote("Spelling changes apply after Crest restarts.")
                }
                BrowserDeveloperToolbarSettingsSection()
            #endif
        }
        .task {
            guard defaultBrowser.status == .unknown else {
                isCheckingDefaultBrowser = false
                return
            }
            await refreshDefaultBrowserStatus()
        }
    }

    #if os(iOS)
        // MARK: - Startup

        /// A phone opens on a new tab in the default Space, or on its tab
        /// viewer, which is its Start Page.
        private var startsOnNewTab: Binding<Bool> {
            Binding {
                appPreferences.startupBehavior.opensNewTab
            } set: { startsOnNewTab in
                appPreferences.startupBehavior = startsOnNewTab ? .newTab : .showStartPage
            }
        }
    #endif

    // MARK: - Default browser

    @ViewBuilder
    private var defaultBrowserStatus: some View {
        if isCheckingDefaultBrowser {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("default-browser-status")
        } else {
            Label(
                defaultBrowser.status.title,
                systemImage: defaultBrowser.status.symbol
            )
            .foregroundStyle(defaultBrowserStatusStyle)
            .accessibilityIdentifier("default-browser-status")
        }
    }

    private var checkAgainButton: some View {
        Button {
            Task { await refreshDefaultBrowserStatus() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help("Check Again")
        .accessibilityLabel("Check Again")
        .disabled(isCheckingDefaultBrowser || defaultBrowser.isWorking)
        .accessibilityIdentifier("check-default-browser-status")
    }

    @ViewBuilder
    private var defaultBrowserActions: some View {
        if defaultBrowser.status != .isDefault {
            let style = defaultBrowser.requestStyle
            Button(style.buttonTitle) {
                style.request(defaultBrowser)
            }
            .disabled(style.waitsForRequest && defaultBrowser.isWorking)
            .accessibilityIdentifier(style.buttonIdentifier)
        }
    }

    @MainActor
    private func refreshDefaultBrowserStatus() async {
        isCheckingDefaultBrowser = true
        defer { isCheckingDefaultBrowser = false }
        await Task.yield()
        guard !Task.isCancelled else { return }
        defaultBrowser.refreshStatus()
    }

    private var defaultBrowserStatusStyle: AnyShapeStyle {
        switch defaultBrowser.status.tone {
        case .quiet: AnyShapeStyle(.secondary)
        case .success: AnyShapeStyle(.green)
        case .warning: AnyShapeStyle(.orange)
        }
    }
}

#if os(macOS)
    /// WebKit reads this spelling preference once per process.
    struct BrowserSpellCheckingToggle: View {
        static let controlIdentifier = "continuous-spell-checking-toggle"

        private let preferences = BrowserAppPreferenceStore.shared

        /// Read while the body evaluates, so the row follows the core's value.
        private var isEnabled: Binding<Bool> {
            let isEnabled = preferences.checksSpelling
            return Binding {
                isEnabled
            } set: {
                preferences.setChecksSpellingForWebKit($0)
            }
        }

        var body: some View {
            Toggle("Check spelling", isOn: isEnabled)
                .accessibilityIdentifier(Self.controlIdentifier)
        }
    }
#endif
