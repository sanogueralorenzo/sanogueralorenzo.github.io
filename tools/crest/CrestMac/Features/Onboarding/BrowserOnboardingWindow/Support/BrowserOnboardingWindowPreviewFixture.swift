import AppKit
import Foundation

@MainActor
struct BrowserOnboardingWindowPreviewFixture {
    let request: BrowserOnboardingRequest
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let spaceAccess: BrowserSpaceAccessController
    let flow: BrowserOnboardingFlow

    init(entryPoint: SetupEntry = .firstRun) {
        let request = BrowserOnboardingRequest(
            entryPoint: entryPoint,
            presentationID: Self.requestID
        )
        let browser = BrowserStore.preview()
        let flow = BrowserOnboardingFlow(
            request: request,
            browser: browser,
            sourceDiscovery: BrowserOnboardingPreviewSourceDiscovery(
                sources: [Self.importSource]
            ),
            dataAccessProvider: BrowserOnboardingPreviewDataAccessProvider(),
            importReader: BrowserOnboardingPreviewImportReader(),
            importCommitter: BrowserOnboardingPreviewImportCommitter()
        )
        flow.discoverInstalledSources()

        self.request = request
        self.browser = browser
        cloudSync = .isolated(core: browser.core)
        progress = BrowserOnboardingProgressStore(
            core: browser.core, environment: BrowserLaunchEnvironment.current.coreEnvironment)
        self.flow = flow
        spaceAccess = BrowserSpaceAccessController(authenticator: BrowserPreviewAuthenticator(result: false))
    }

    static let importSource = BrowserInstalledImportSource(
        application: .arc,
        applicationURL: URL(
            fileURLWithPath: "/Applications/Preview Browser.app"
        ),
        detectedPayload: BrowserDetectedImportPayload(
            application: .arc,
            profiles: []
        ),
        icon: NSImage(
            systemSymbolName: "safari.fill",
            accessibilityDescription: "Preview browser"
        ) ?? NSImage(size: NSSize(width: 54, height: 54))
    )

    private static let requestID = UUID(
        uuid: (
            0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
            0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x01
        )
    )
}
