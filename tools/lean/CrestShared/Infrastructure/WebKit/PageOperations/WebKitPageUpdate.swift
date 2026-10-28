import Foundation

enum WebKitPageUpdate: Equatable, Sendable {
    case audioSpectrumChanged(AudioSpectrumChanged)
    case contentFullscreenChanged(ContentFullscreenChanged)
    case contentMessagePosted(ContentMessagePosted)
    case contentScriptEvaluated(ContentScriptEvaluated)
    case extensionsChanged(ExtensionsChanged)
    case findFinished(FindFinished)
    case infoBarRemoved(InfoBarRemoved)
    case infoBarShown(InfoBarShown)
    case inspectorClosed(InspectorClosed)
    case inspectorLayoutChanged(InspectorLayoutChanged)
    case linkHovered(LinkHovered)
    case mediaSessionChanged(MediaSessionChanged)
    case pageCaptured(PageCaptured)
    case pageExported(PageExported)
    case pageInputDelivered(PageInputDelivered)
    case pageInteracted(PageInteracted)
    case pageLoadingChanged(PageLoadingChanged)
    case pageNavigationCommitted(PageNavigationCommitted)
    case pageNavigationFailed(PageNavigationFailed)
    case pageNavigationStarted(PageNavigationStarted)
    case pageRendererGone(PageRendererGone)
    case pageScriptEvaluated(PageScriptEvaluated)
    case pageThemeChanged(PageThemeChanged)
    case pageViewClosed(PageViewClosed)
    case pageViewReady(PageViewReady)
    case pageViewUnavailable(PageViewUnavailable)
    case popupBlocked(PopupBlocked)
    case profileNotificationClosed(ProfileNotificationClosed)
    case profileNotificationPosted(ProfileNotificationPosted)
    case profilePrepared(ProfilePrepared)
    case profileReleased(ProfileReleased)
    case screenCaptureAccessMissing(ScreenCaptureAccessMissing)
    case shareSourcesOffered(ShareSourcesOffered)
    case shareSourcesWithdrawn(ShareSourcesWithdrawn)
    case sidePanelRequested(SidePanelRequested)
    case storeInstallRequested(StoreInstallRequested)
    case storeRemovalRequested(StoreRemovalRequested)
    case tabSharingChanged(TabSharingChanged)
    case webNotificationClosed(WebNotificationClosed)
    case webNotificationPosted(WebNotificationPosted)

    /// The `PageId` every member of the core's `EnginePagePresentation` carries, or nil for any other.
    var pageID: UUID? {
        switch self {
        case .extensionsChanged, .profileNotificationClosed, .profileNotificationPosted, .profilePrepared,
            .profileReleased:
            nil
        case .audioSpectrumChanged(let value): value.pageID
        case .contentFullscreenChanged(let value): value.pageID
        case .contentMessagePosted(let value): value.pageID
        case .contentScriptEvaluated(let value): value.pageID
        case .findFinished(let value): value.pageID
        case .infoBarRemoved(let value): value.pageID
        case .infoBarShown(let value): value.pageID
        case .inspectorClosed(let value): value.pageID
        case .inspectorLayoutChanged(let value): value.pageID
        case .linkHovered(let value): value.pageID
        case .mediaSessionChanged(let value): value.pageID
        case .pageCaptured(let value): value.pageID
        case .pageExported(let value): value.pageID
        case .pageInputDelivered(let value): value.pageID
        case .pageInteracted(let value): value.pageID
        case .pageLoadingChanged(let value): value.pageID
        case .pageNavigationCommitted(let value): value.pageID
        case .pageNavigationFailed(let value): value.pageID
        case .pageNavigationStarted(let value): value.pageID
        case .pageRendererGone(let value): value.pageID
        case .pageScriptEvaluated(let value): value.pageID
        case .pageThemeChanged(let value): value.pageID
        case .pageViewClosed(let value): value.pageID
        case .pageViewReady(let value): value.pageID
        case .pageViewUnavailable(let value): value.pageID
        case .popupBlocked(let value): value.pageID
        case .screenCaptureAccessMissing(let value): value.pageID
        case .shareSourcesOffered(let value): value.pageID
        case .shareSourcesWithdrawn(let value): value.pageID
        case .sidePanelRequested(let value): value.pageID
        case .storeInstallRequested(let value): value.pageID
        case .storeRemovalRequested(let value): value.pageID
        case .tabSharingChanged(let value): value.pageID
        case .webNotificationClosed(let value): value.pageID
        case .webNotificationPosted(let value): value.pageID
        }
    }
}

struct AudioSpectrumChanged: Equatable, Sendable {
    let pageID: UUID
    let bands: Data
}

struct ContentFullscreenChanged: Equatable, Sendable {
    let pageID: UUID
    let active: Bool
}

struct ContentMessagePosted: Equatable, Sendable {
    let pageID: UUID
    let handler: String
    let body: String
    let frame: ContentFrame
}

struct ContentScriptEvaluated: Equatable, Sendable {
    let pageID: UUID
    let evaluationID: UUID
    let json: String?
}

struct ExtensionsChanged: Equatable, Sendable {
    let profileID: UUID
}

struct FindFinished: Equatable, Sendable {
    let pageID: UUID
    let matches: Int?
    let activeMatch: Int
}

struct InfoBarRemoved: Equatable, Sendable {
    let pageID: UUID
    let infoBarID: Int
}

struct InfoBarShown: Equatable, Sendable {
    let pageID: UUID
    let infoBarID: Int
    let message: String
    let acceptLabel: String?
    let cancelLabel: String?
    let closeable: Bool
    let minimizable: Bool
}

struct InspectorClosed: Equatable, Sendable {
    let pageID: UUID
}

struct InspectorLayoutChanged: Equatable, Sendable {
    let pageID: UUID
}

struct LinkHovered: Equatable, Sendable {
    let pageID: UUID
    let url: String?
}

struct MediaSessionChanged: Equatable, Sendable {
    let pageID: UUID
    let document: String
    let sequence: Int64
    let location: String
    let active: Bool
    let title: String?
    let artist: String?
    let album: String?
    let artwork: Data?
    let playback: MediaPlayback
    let audible: Bool
    let muted: Bool
    let actions: [MediaSessionAction]
}

struct PageCaptured: Equatable, Sendable {
    let pageID: UUID
    let captureID: UUID
    let png: Data?
}

struct PageExported: Equatable, Sendable {
    let pageID: UUID
    let exportID: UUID
    let document: Data?
    let failure: PageExportFailure?
}

struct PageInputDelivered: Equatable, Sendable {
    let pageID: UUID
    let inputID: UUID
    let delivered: Bool
    let trusted: Bool
}

struct PageInteracted: Equatable, Sendable {
    let pageID: UUID
}

struct PageLoadingChanged: Equatable, Sendable {
    let pageID: UUID
    let isLoading: Bool
}

struct PageNavigationCommitted: Equatable, Sendable {
    let pageID: UUID
    let url: String
    let isLoading: Bool
}

struct PageNavigationFailed: Equatable, Sendable {
    let pageID: UUID
}

struct PageNavigationStarted: Equatable, Sendable {
    let pageID: UUID
}

struct PageRendererGone: Equatable, Sendable {
    let pageID: UUID
}

struct PageScriptEvaluated: Equatable, Sendable {
    let pageID: UUID
    let evaluationID: UUID
    let json: String?
    let error: String?
}

struct PageThemeChanged: Equatable, Sendable {
    let pageID: UUID
    let color: BrandColor?
}

struct PageViewClosed: Equatable, Sendable {
    let pageID: UUID
}

struct PageViewReady: Equatable, Sendable {
    let pageID: UUID
}

struct PageViewUnavailable: Equatable, Sendable {
    let pageID: UUID
}

struct PopupBlocked: Equatable, Sendable {
    let pageID: UUID
    let pageURL: String
}

struct ProfileNotificationClosed: Equatable, Sendable {
    let profileID: UUID
    let notificationID: String
}

struct ProfileNotificationPosted: Equatable, Sendable {
    let profileID: UUID
    let notificationID: String
    let origin: SiteOrigin
    let source: ProfileNotificationSource
    let title: String
    let body: String
    let silent: Bool
}

struct ProfilePrepared: Equatable, Sendable {
    let preparationID: UUID
    let ready: Bool
}

struct ProfileReleased: Equatable, Sendable {
    let profileID: UUID
}

struct ScreenCaptureAccessMissing: Equatable, Sendable {
    let pageID: UUID
}

struct ShareSourcesOffered: Equatable, Sendable {
    let pageID: UUID
    let shareID: UUID
    let site: String
    let tabs: [ShareableTab]
    let audio: Bool
}

struct ShareSourcesWithdrawn: Equatable, Sendable {
    let pageID: UUID
    let shareID: UUID
}

struct SidePanelRequested: Equatable, Sendable {
    let pageID: UUID
    let extensionID: String
    let request: SidePanelRequest
}

struct StoreInstallRequested: Equatable, Sendable {
    let pageID: UUID
    let extensionID: String
}

struct StoreRemovalRequested: Equatable, Sendable {
    let pageID: UUID
    let extensionID: String
}

struct TabSharingChanged: Equatable, Sendable {
    let pageID: UUID
    let shared: Bool
    let sharing: Bool
}

struct WebNotificationClosed: Equatable, Sendable {
    let pageID: UUID
    let notificationID: String
}

struct WebNotificationPosted: Equatable, Sendable {
    let pageID: UUID
    let notificationID: String
    let origin: SiteOrigin
    let title: String
    let body: String
    let silent: Bool
}
