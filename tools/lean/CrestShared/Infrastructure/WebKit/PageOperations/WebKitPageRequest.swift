import Foundation

/// Local WebKit work; these operations never cross a language or engine boundary.
protocol WebKitPageRequest: Sendable {
    associatedtype Answer: Sendable
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer
}

struct ActivateMediaSession: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let document: String
}

struct AddContentScript: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let source: String
    let mainFrameOnly: Bool
}

struct AnswerInfoBar: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let infoBarID: Int
    let answer: InfoBarAnswer
}

struct AnswerProfileNotification: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let profileID: UUID
    let notificationID: String
    let answer: WebNotificationAnswer
}

struct AnswerWebNotification: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let notificationID: String
    let answer: WebNotificationAnswer
}

struct CapturePage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let captureID: UUID
    let area: PageArea?
    let width: Double
}

struct ChangeExtension: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let profileID: UUID
    let extensionID: String
    let change: ExtensionChange
}

struct ChooseShareSource: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let shareID: UUID
    let choice: ShareSourceChoice
    let tabPageID: UUID?
    let audio: Bool
}

struct ClickPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let inputID: UUID
    let point: PagePoint
    let button: PointerButton
    let count: Int
    let modifiers: KeyModifiers
}

struct CloseInspector: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct EnterPictureInPicture: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct EvaluateContentScript: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let evaluationID: UUID
    let source: String
    let frameID: String
}

struct EvaluatePageScript: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let evaluationID: UUID
    let source: String
    let world: PageScriptWorld
}

struct ExportPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let exportID: UUID
    let format: PageExportFormat
    let width: Double
}

struct FindInPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let query: String
    let backwards: Bool
    let caseSensitive: Bool
}

struct HasSidePanel: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = SidePanelScope

    let pageID: UUID
    let extensionID: String
}

struct HidePage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct HoldPageRendering: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let held: Bool
    let width: Double
    let height: Double
}

struct HoverPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let inputID: UUID
    let point: PagePoint
}

struct InstalledExtensions: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = InstalledExtensionList

    let profileID: UUID
}

struct LayoutInspector: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = InspectorLayout

    let pageID: UUID
    let width: Double
    let height: Double
}

struct MovePageToWindow: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let windowID: UUID
}

struct MuteMediaSession: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let document: String
    let muted: Bool
}

struct ObserveAudioSpectrum: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let observed: Bool
}

struct ObservePageActivity: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let observing: Bool
}

struct OpenInspector: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let panel: InspectorPanel?
}

struct PageCertificates: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = CertificateChain

    let pageID: UUID
}

struct PageExtensions: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = ExtensionActionList

    let pageID: UUID
}

struct PageIcon: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = PageIconImage

    let pageID: UUID
}

struct PageInspected: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct PageMedia: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = PageMediaState

    let pageID: UUID
}

struct PerformMediaAction: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let document: String
    let action: MediaSessionAction
}

struct PinnedExtensions: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = ExtensionActionList

    let profileID: UUID
}

struct PrepareProfile: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let profileID: UUID
    let preparationID: UUID
}

struct PressKeyInPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let inputID: UUID
    let key: PageKey
    let modifiers: KeyModifiers
}

struct ReadPageConsole: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = PageConsoleLog

    let pageID: UUID
    let after: Int64
}

struct ReadPageNetwork: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = PageNetworkLog

    let pageID: UUID
    let after: Int64
}

struct RefreshPageIcon: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct RefreshStoreListing: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct ReloadPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let bypassesCache: Bool
}

struct RestoreInteractionState: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let state: Data
    let expectedURL: String
}

struct SaveInteractionState: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = InteractionState

    let pageID: UUID
}

struct ScrollPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let inputID: UUID
    let point: PagePoint
    let deltaX: Double
    let deltaY: Double
}

struct SetSitePermission: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let permission: SitePermission
    let allowed: Bool?
}

struct ShowBlockedPopups: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct ShowPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct StopLoading: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct StopMediaCapture: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let permission: SitePermission
}

struct StopTabSharing: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct TypeInPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let inputID: UUID
    let text: String
}

struct WatchPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
}

struct ZoomPage: WebKitPageRequest, Equatable, Sendable {
    typealias Answer = Bool

    let pageID: UUID
    let factor: Double
}
