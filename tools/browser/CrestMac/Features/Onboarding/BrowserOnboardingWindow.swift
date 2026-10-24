import SwiftUI

struct BrowserOnboardingWindow: View {
    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let spaceAccess: BrowserSpaceAccessController
    /// Closes the window setup shows in.
    private let closeWindow: () -> Void
    /// Brings the browser forward once setup finished: the window setup was
    /// opened from, or the launch it held back.
    private let openBrowser: () -> Void

    @State private var flow: BrowserOnboardingFlow
    /// How long the welcome has waited on iCloud's check.
    @State private var cloudWait = BrowserOnboardingCloudWait()
    @State private var selectedManualSpaceID: UUID?
    @State private var customizationSpaceID: UUID?

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        extensionInstaller: (any BrowserImportedExtensionInstalling)?,
        closeWindow: @escaping () -> Void,
        openBrowser: @escaping () -> Void
    ) {
        self.init(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            spaceAccess: spaceAccess,
            flow: BrowserOnboardingFlow(request: request, browser: browser, extensionInstaller: extensionInstaller),
            closeWindow: closeWindow, openBrowser: openBrowser
        )
    }

    init(
        request: BrowserOnboardingRequest,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        flow: BrowserOnboardingFlow,
        closeWindow: @escaping () -> Void,
        openBrowser: @escaping () -> Void
    ) {
        self.request = request
        self.cloudSync = cloudSync
        self.progress = progress
        self.spaceAccess = spaceAccess
        self.closeWindow = closeWindow
        self.openBrowser = openBrowser
        _flow = State(initialValue: flow)
        _selectedManualSpaceID = State(initialValue: flow.manualSetup.spaces.first?.spaceID)
        _customizationSpaceID = State(initialValue: nil)
    }

    var body: some View {
        BrowserOnboardingWindowContent(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            flow: flow,
            cloudWait: cloudWait,
            selectedManualSpaceID: $selectedManualSpaceID,
            customizationSpaceID: $customizationSpaceID,
            close: closeWindow,
            openCrest: openCrest
        )
        .environment(flow.browser.core)
    }

    private func openCrest() {
        flow.completeSetup(progress: progress, spaceAccess: spaceAccess) {
            openBrowser()
            closeWindow()
        }
    }
}

#Preview("Onboarding Window") {
    let fixture = BrowserOnboardingWindowPreviewFixture()
    BrowserOnboardingWindow(
        request: fixture.request,
        cloudSync: fixture.cloudSync,
        progress: fixture.progress,
        spaceAccess: fixture.spaceAccess,
        flow: fixture.flow,
        closeWindow: {},
        openBrowser: {}
    )
    .frame(width: 980, height: 660)
}
