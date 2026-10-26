import SwiftUI

struct BrowserImportWindow: View {
    let closeWindow: () -> Void
    @State private var flow: BrowserImportFlow
    @State private var customizationSpaceID: UUID?

    init(
        browser: BrowserStore, extensionInstaller: (any BrowserImportedExtensionInstalling)?,
        closeWindow: @escaping () -> Void
    ) {
        self.closeWindow = closeWindow
        _flow = State(initialValue: BrowserImportFlow(browser: browser, extensionInstaller: extensionInstaller))
    }

    var body: some View {
        Group {
            if let customizationSpaceID, flow.review != nil {
                BrowserImportSpaceCustomizationView(
                    flow: flow, spaceID: customizationSpaceID,
                    previewSpace: flow.customizationPreviewSpace(customizationSpaceID),
                    done: { self.customizationSpaceID = nil })
            } else {
                importPage
            }
        }
        .environment(flow.browser.core)
        .frame(minWidth: 980, minHeight: 660)
        .foregroundStyle(CrestBrandTheme.textDisplay)
        .background(CrestBrandTheme.canvas)
        .tint(CrestBrandTheme.accent)
        .task {
            flow.start()
            flow.discoverInstalledSources()
        }
        .onDisappear(perform: flow.cancelOperations)
    }

    @ViewBuilder
    private var importPage: some View {
        switch flow.step.kind {
        case .importBrowser:
            BrowserImportPage(
                sources: flow.offeredSources, isSelected: flow.isSelected,
                hasScanned: flow.hasScanned, unlistedCount: flow.unlistedSources.count,
                isReading: flow.isReading,
                failure: flow.failure?.message, accessLabel: flow.importAccessLabel,
                toggleSelection: flow.toggleSelection, scanForMore: flow.scanForMore,
                continueImport: flow.continueImportQueue, cancelRead: flow.cancelImportRead,
                back: BrowserImportBackAction(closes: true, action: closeWindow))
        case .review:
            BrowserImportReviewPage(
                flow: flow, customizationSpaceID: $customizationSpaceID,
                back: BrowserImportBackAction(closes: false, action: { flow.show(.importBrowser) }))
        case .complete:
            VStack(spacing: 24) {
                Text("Import Complete").font(.title)
                if let summary = flow.completionSummary { Text(summary) }
                Button("Done", action: closeWindow).buttonStyle(.crestPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct BrowserImportBackAction {
    let closes: Bool
    let action: () -> Void
}
