import SwiftUI

struct BrowserShortcutSettingsView: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var model: BrowserShortcutSettingsModel

    private let requestedSpaceID: UUID?
    private let requestRevision: Int

    init(
        shortcuts: BrowserShortcutStore,
        requestedSpaceID: UUID? = nil,
        requestRevision: Int = 0
    ) {
        self.init(
            model: BrowserShortcutSettingsModel(
                shortcuts: shortcuts,
                searchProvider: BrowserShortcutPresentationCatalog()
            ),
            requestedSpaceID: requestedSpaceID,
            requestRevision: requestRevision
        )
    }

    init(
        model: BrowserShortcutSettingsModel,
        requestedSpaceID: UUID? = nil,
        requestRevision: Int = 0
    ) {
        _model = State(initialValue: model)
        self.requestedSpaceID = requestedSpaceID
        self.requestRevision = requestRevision
    }

    var body: some View {
        BrowserShortcutSettingsContent(
            model: tabState?.retainShortcuts(model) ?? model,
            requestedSpaceID: requestedSpaceID,
            requestRevision: requestRevision
        )
    }
}

private struct BrowserShortcutSettingsContent: View {
    @Environment(\.locale) private var locale
    @Bindable var model: BrowserShortcutSettingsModel
    @State private var showsResetConfirmation = false

    let requestedSpaceID: UUID?
    let requestRevision: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserShortcutSettingsMetrics.contentSpacing
        ) {
            BrowserShortcutSettingsControls(
                searchText: $model.searchText,
                canReset: model.hasCrestCustomizations,
                requestReset: { showsResetConfirmation = true }
            )

            if let issue = model.validationIssue {
                BrowserShortcutValidationBanner(issue: issue)
            }

            BrowserShortcutList(model: model)

            Text(BrowserShortcutSettingsPresentation.guidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: BrowserSettingsLayout.formColumnWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 20)
        .padding(.horizontal, BrowserSettingsLayout.formMinimumInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(
            BrowserShortcutSettingsPresentation.shortcutAlreadyInUse,
            isPresented: $model.isPresentingConflict
        ) {
            Button(
                BrowserShortcutSettingsPresentation.replaceExistingShortcut,
                action: model.replacePendingConflict
            )
            Button(
                BrowserShortcutSettingsPresentation.cancel,
                role: .cancel,
                action: model.cancelPendingConflict
            )
        } message: {
            Text(
                model.pendingConflict?.messageResource(locale: locale)
                    ?? BrowserShortcutLocalization.resource(
                        BrowserShortcutSettingsPresentation
                            .chooseAnotherShortcut,
                        locale: locale
                    )
            )
        }
        .confirmationDialog(
            BrowserShortcutSettingsPresentation.resetAllPrompt,
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                BrowserShortcutSettingsPresentation.resetCrestShortcuts,
                role: .destructive,
                action: model.resetAllCrestShortcuts
            )
        } message: {
            Text(BrowserShortcutSettingsPresentation.resetAllDetail)
        }
        .onDisappear { model.cancelPendingConflict() }
        .onChange(of: locale.identifier, initial: true) {
            model.updateSearchProvider(
                BrowserShortcutPresentationCatalog(locale: locale)
            )
        }
    }
}

private struct BrowserShortcutValidationBanner: View {
    @Environment(\.locale) private var locale

    let issue: BrowserShortcutValidationIssue

    var body: some View {
        Label(
            issue.messageResource(locale: locale),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier(
            BrowserShortcutSettingsAccessibilityID.validationMessage
        )
    }
}
