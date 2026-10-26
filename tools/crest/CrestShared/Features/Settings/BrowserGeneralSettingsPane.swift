import SwiftUI

/// Browsing preferences and the platform's default-browser actions.
struct BrowserGeneralSettingsPane: View {
    let browser: BrowserStore

    @State private var defaultBrowser = BrowserDefaultBrowserController()
    @State private var isCheckingDefaultBrowser = true
    #if os(iOS)
        @AppStorage(
            MobileBrowserRootPreferences.allowsFloatingSidebarKey, store: BrowserChromeAppearancePreference.defaults)
        private var allowsFloatingSidebar = false
    #endif

    init(browser: BrowserStore) {
        self.browser = browser
    }

    var body: some View {
        BrowserSettingsPane(.general) {
            BrowserDefaultPageZoomSettingsSection()
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

            BrowserSearchProviderSettingsSection()
            BrowserTranslationSettingsSection()

            #if os(iOS)
                Section("Sidebar") {
                    Toggle("Allow floating sidebar", isOn: $allowsFloatingSidebar)
                        .accessibilityIdentifier("allow-floating-sidebar")
                }
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
