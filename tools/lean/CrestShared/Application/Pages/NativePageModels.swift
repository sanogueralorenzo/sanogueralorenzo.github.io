import Foundation
import Observation

struct OpenPage: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let workspaceID: UUID
    let spaceID: UUID
    let tabID: UUID?
    let windowID: UUID
    let transient: TransientPresentation?
    let openerPageID: UUID?
}

struct MovePage: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let workspaceID: UUID
    let spaceID: UUID
    let tabID: UUID?
    let windowID: UUID
}

struct ReleasePage: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let keepsState: Bool
}

struct Navigate: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let input: String
}

struct LoadAddress: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let url: String
}

struct LeavePageFailure: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
}

struct StepHistory: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let offset: Int
}

struct ShowHistoryEntry: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let entryID: UUID
}

struct RestoreTabHistory: NativePageRequest, Equatable, Sendable {
    let workspaceID: UUID
    let spaceID: UUID
    let tabID: UUID
    let archive: Data
}

struct StageLink: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let sourcePageID: UUID
    let stagedLinkID: UUID
    let url: String
}

struct DiscardStagedLink: NativePageRequest, Equatable, Sendable {
    let sourcePageID: UUID
    let stagedLinkID: UUID
}

struct UnloadIdlePage: NativePageRequest, Equatable, Sendable {
    let pageID: UUID
    let documents: Int64
    let hiddenSince: Date
}

struct ReportMemoryPressure: NativePageRequest, Equatable, Sendable {
    let level: MemoryPressureLevel
}

struct PageCreated: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
}

struct PageCreationFailed: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
}

struct PageClosed: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let restoreState: PageRestoreState?
}

struct PageCloseRequested: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
}

struct PageCrashed: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let domain: String
    let code: Int64
}

struct PageStateChanged: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let snapshot: PageSnapshot
}

struct PageHistoryReported: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let entries: [PageHistoryEntry]
    let current: Int
}

struct PageIconChanged: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let url: String
    let accent: TabIconAccent?
}

struct NavigationStarted: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let url: String
    let sameDocument: Bool
}

struct NavigationCommitted: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let url: String
    let sameDocument: Bool
}

struct NavigationFinished: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let url: String
    let title: String
}

struct NavigationFailed: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
    let failure: PageFailure
}

struct StagedLinkUnavailable: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
}

struct PictureInPictureReturned: NativeDocumentReport, Equatable, Sendable {
    let pageID: UUID
}

struct PageOffered: NativePageReport, Equatable, Sendable {
    let offerID: UUID
    let profileID: UUID
    let sourcePageID: UUID?
    let windowID: UUID?
    let spaceID: UUID?
    let url: String
    let foreground: Bool
}

struct AdoptOfferedPage: Equatable, Sendable {
    let pageID: UUID
    let offerID: UUID
    let profileID: UUID
    let isPrivate: Bool
    let windowID: UUID
}

struct ClosePage: Equatable, Sendable {
    let pageID: UUID
    let keepsState: Bool
}

struct CreatePage: Equatable, Sendable {
    let pageID: UUID
    let profileID: UUID
    let isPrivate: Bool
    let windowID: UUID
    let restoreState: PageRestoreState?
}

struct ExitPictureInPicture: Equatable, Sendable {
    let pageID: UUID
}

struct GoToHistoryEntry: Equatable, Sendable {
    let pageID: UUID
    let entryID: UUID
}

struct LoadPage: Equatable, Sendable {
    let pageID: UUID
    let url: String
    let entryID: UUID?
}

struct RecoverPage: Equatable, Sendable {
    let pageID: UUID
}

struct RejectOfferedPage: Equatable, Sendable {
    let offerID: UUID
}

struct DropStagedLink: Equatable, Sendable {
    let stagedLinkID: UUID
}

struct StageNavigation: Equatable, Sendable {
    let pageID: UUID
    let stagedLinkID: UUID
    let url: String
}

struct PageState: Equatable, Sendable, Identifiable {
    let id: UUID
    let workspaceID: UUID
    let spaceID: UUID
    let tabID: UUID?
    let phase: PagePhase
    let live: PageLiveState
    let windowID: UUID
    let documents: Int64
}

@Observable
final class PageStateModel: ObservedModel, Identifiable {
    let id: UUID
    var workspaceID: UUID {
        access(keyPath: \.workspaceID)
        return workspaceIDStorage
    }
    var spaceID: UUID {
        access(keyPath: \.spaceID)
        return spaceIDStorage
    }
    var tabID: UUID? {
        access(keyPath: \.tabID)
        return tabIDStorage
    }
    var phase: PagePhase {
        access(keyPath: \.phase)
        return phaseStorage
    }
    var live: PageLiveState {
        access(keyPath: \.live)
        return liveStorage
    }
    var windowID: UUID {
        access(keyPath: \.windowID)
        return windowIDStorage
    }
    var documents: Int64 {
        access(keyPath: \.documents)
        return documentsStorage
    }

    @ObservationIgnored private var workspaceIDStorage: UUID
    @ObservationIgnored private var spaceIDStorage: UUID
    @ObservationIgnored private var tabIDStorage: UUID?
    @ObservationIgnored private var phaseStorage: PagePhase
    @ObservationIgnored private var liveStorage: PageLiveState
    @ObservationIgnored private var windowIDStorage: UUID
    @ObservationIgnored private var documentsStorage: Int64

    var value: PageState {
        PageState(
            id: id,
            workspaceID: workspaceID,
            spaceID: spaceID,
            tabID: tabID,
            phase: phase,
            live: live,
            windowID: windowID,
            documents: documents
        )
    }

    init(_ value: PageState) {
        id = value.id
        workspaceIDStorage = value.workspaceID
        spaceIDStorage = value.spaceID
        tabIDStorage = value.tabID
        phaseStorage = value.phase
        liveStorage = value.live
        windowIDStorage = value.windowID
        documentsStorage = value.documents
    }

    func update(_ value: PageState) {
        precondition(value.id == id, "A PageStateModel takes only its own PageState's values.")
        if workspaceIDStorage != value.workspaceID {
            workspaceIDStorage = value.workspaceID
            withMutation(keyPath: \.workspaceID) {}
        }
        if spaceIDStorage != value.spaceID {
            spaceIDStorage = value.spaceID
            withMutation(keyPath: \.spaceID) {}
        }
        if tabIDStorage != value.tabID {
            tabIDStorage = value.tabID
            withMutation(keyPath: \.tabID) {}
        }
        if phaseStorage != value.phase {
            phaseStorage = value.phase
            withMutation(keyPath: \.phase) {}
        }
        if liveStorage != value.live {
            liveStorage = value.live
            withMutation(keyPath: \.live) {}
        }
        if windowIDStorage != value.windowID {
            windowIDStorage = value.windowID
            withMutation(keyPath: \.windowID) {}
        }
        if documentsStorage != value.documents {
            documentsStorage = value.documents
            withMutation(keyPath: \.documents) {}
        }
    }
}

struct PageSnapshot: Equatable, Sendable {
    static let blank = PageSnapshot(
        url: nil, pendingURL: nil, title: "", isLoading: false, security: PageSecurity.none, media: [])

    var url: String?
    var pendingURL: String?
    var title: String
    var isLoading: Bool
    var security: PageSecurity
    var media: PageMediaActivity
}

struct PageLiveState: Equatable, Sendable {
    static let blank = PageLiveState(
        url: nil,
        pendingURL: nil,
        title: "",
        isLoading: false,
        canGoBack: false,
        canGoForward: false,
        security: PageSecurity.none,
        failure: nil,
        media: [],
        address: nil
    )

    let url: String?
    let pendingURL: String?
    let title: String
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let security: PageSecurity
    let failure: PageFailure?
    let media: PageMediaActivity
    let address: String?
}

struct PageFailure: Equatable, Sendable {
    var error: NavigationError
    var url: String?
    var replacedDocument: Bool
    var domain: String
    var code: Int64
}

struct PageHistoryEntry: Equatable, Sendable, Identifiable {
    var id: UUID
    var url: String
    var title: String
}

struct PageHistoryList: Equatable, Sendable {
    let back: [PageHistoryEntry]
    let forward: [PageHistoryEntry]
}

struct PageHistoryArchive: Equatable, Sendable {
    let archive: Data?
}

struct PageRestoreState: Equatable, Sendable {
    var url: String
    var state: Data
}

struct IdlePageCandidate: Equatable, Sendable {
    let pageID: UUID
    let documents: Int64
    let hiddenSince: Date
}

struct IdlePageList: Equatable, Sendable {
    let pages: [IdlePageCandidate]
}

struct SavedAddressReturn: Equatable, Sendable {
    let changesPage: Bool
}

struct PageOpened: CoreChange, Equatable, Sendable {
    let page: PageState
}

struct PageChanged: CoreChange, Equatable, Sendable {
    let page: PageState
}

struct PageRemoved: CoreChange, Equatable, Sendable {
    let pageID: UUID
}

struct PageUnloaded: CoreChange, Equatable, Sendable {
    let pageID: UUID
    let workspaceID: UUID
    let tabID: UUID
}

struct OfferedPageAdopted: CoreChange, Equatable, Sendable {
    let pageID: UUID
    let workspaceID: UUID
    let windowID: UUID
    let spaceID: UUID
    let tabID: UUID
    let shows: Bool
}

struct TransientPageClosed: CoreChange, Equatable, Sendable {
    let pageID: UUID
    let workspaceID: UUID
}

struct PagePhase: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var holdsEnginePage: Bool { facts.holdsEnginePage }
    private let facts: Facts

    private init(tag: Int, name: String, holdsEnginePage: Bool) {
        self.tag = tag
        facts = Facts(name: name, holdsEnginePage: holdsEnginePage)
    }

    static let opening = PagePhase(tag: 0, name: "opening", holdsEnginePage: true)
    static let live = PagePhase(tag: 1, name: "live", holdsEnginePage: true)
    static let failed = PagePhase(tag: 2, name: "failed", holdsEnginePage: false)
    static let closed = PagePhase(tag: 3, name: "closed", holdsEnginePage: false)

    static let all: [PagePhase] = [opening, live, failed, closed]

    static func named(_ name: String?) -> PagePhase? {
        all.first { $0.name == name }
    }

    static func == (lhs: PagePhase, rhs: PagePhase) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let holdsEnginePage: Bool

        init(name: String, holdsEnginePage: Bool) {
            self.name = name
            self.holdsEnginePage = holdsEnginePage
        }
    }
}

struct PageSecurity: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var title: LocalizedStringResource { facts.title }
    var symbol: String { facts.symbol }
    var detail: LocalizedStringResource? { facts.detail }
    var isSecure: Bool { facts.isSecure }
    var isHazardous: Bool { facts.isHazardous }
    private let facts: Facts

    private init(
        tag: Int,
        name: String,
        title: LocalizedStringResource,
        symbol: String,
        detail: LocalizedStringResource?,
        isSecure: Bool,
        isHazardous: Bool
    ) {
        self.tag = tag
        facts = Facts(
            name: name,
            title: title,
            symbol: symbol,
            detail: detail,
            isSecure: isSecure,
            isHazardous: isHazardous
        )
    }

    static let none = PageSecurity(
        tag: 0,
        name: "none",
        title: LocalizedStringResource("Not Secure"),
        symbol: "lock.open.fill",
        detail: nil,
        isSecure: false,
        isHazardous: false
    )
    static let insecure = PageSecurity(
        tag: 1,
        name: "insecure",
        title: LocalizedStringResource("Not Secure"),
        symbol: "lock.open.fill",
        detail: nil,
        isSecure: false,
        isHazardous: false
    )
    static let secure = PageSecurity(
        tag: 2,
        name: "secure",
        title: LocalizedStringResource("Secure"),
        symbol: "lock.fill",
        detail: nil,
        isSecure: true,
        isHazardous: false
    )
    static let mixedContent = PageSecurity(
        tag: 3,
        name: "mixed_content",
        title: LocalizedStringResource("Partly Secure"),
        symbol: "lock.trianglebadge.exclamationmark.fill",
        detail: LocalizedStringResource("Some content on this page was not delivered securely."),
        isSecure: false,
        isHazardous: false
    )
    static let certificateError = PageSecurity(
        tag: 4,
        name: "certificate_error",
        title: LocalizedStringResource("Certificate Not Trusted"),
        symbol: "exclamationmark.lock.fill",
        detail: LocalizedStringResource(
            "This site’s certificate is not trusted. Information you send could be read by others."),
        isSecure: false,
        isHazardous: true
    )
    static let dangerous = PageSecurity(
        tag: 5,
        name: "dangerous",
        title: LocalizedStringResource("Dangerous Site"),
        symbol: "exclamationmark.octagon.fill",
        detail: LocalizedStringResource("This site may try to harm your Mac or steal your information."),
        isSecure: false,
        isHazardous: true
    )

    static let all: [PageSecurity] = [none, insecure, secure, mixedContent, certificateError, dangerous]

    static func named(_ name: String?) -> PageSecurity? {
        all.first { $0.name == name }
    }

    static func == (lhs: PageSecurity, rhs: PageSecurity) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let title: LocalizedStringResource
        let symbol: String
        let detail: LocalizedStringResource?
        let isSecure: Bool
        let isHazardous: Bool

        init(
            name: String,
            title: LocalizedStringResource,
            symbol: String,
            detail: LocalizedStringResource?,
            isSecure: Bool,
            isHazardous: Bool
        ) {
            self.name = name
            self.title = title
            self.symbol = symbol
            self.detail = detail
            self.isSecure = isSecure
            self.isHazardous = isHazardous
        }
    }
}

struct PageMediaActivity: OptionSet, Sendable {
    let rawValue: Int
    static let playing = PageMediaActivity(rawValue: 1)
    static let capturing = PageMediaActivity(rawValue: 2)
    static let pictureInPicture = PageMediaActivity(rawValue: 4)
}

struct TransientPresentation: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    private let facts: Facts

    private init(tag: Int, name: String) {
        self.tag = tag
        facts = Facts(name: name)
    }

    static let settings = TransientPresentation(tag: 0, name: "settings")
    static let authentication = TransientPresentation(tag: 1, name: "authentication")

    static let all: [TransientPresentation] = [settings, authentication]

    static func named(_ name: String?) -> TransientPresentation? {
        all.first { $0.name == name }
    }

    static func == (lhs: TransientPresentation, rhs: TransientPresentation) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String

        init(name: String) {
            self.name = name
        }
    }
}

struct NavigationError: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var code: String { facts.code }
    var title: LocalizedStringResource { facts.title }
    var message: LocalizedStringResource { facts.message }
    var primarySuggestion: LocalizedStringResource { facts.primarySuggestion }
    var secondarySuggestion: LocalizedStringResource { facts.secondarySuggestion }
    var symbol: String { facts.symbol }
    private let facts: Facts

    private init(
        tag: Int,
        name: String,
        code: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        primarySuggestion: LocalizedStringResource,
        secondarySuggestion: LocalizedStringResource,
        symbol: String
    ) {
        self.tag = tag
        facts = Facts(
            name: name,
            code: code,
            title: title,
            message: message,
            primarySuggestion: primarySuggestion,
            secondarySuggestion: secondarySuggestion,
            symbol: symbol
        )
    }

    static let offline = NavigationError(
        tag: 0,
        name: "offline",
        code: "CREST_INTERNET_DISCONNECTED",
        title: LocalizedStringResource("You’re offline"),
        message: LocalizedStringResource("Crest can’t reach %@ without a network connection."),
        primarySuggestion: LocalizedStringResource("Reconnect to Wi-Fi or Ethernet, then try again."),
        secondarySuggestion: LocalizedStringResource("If you use a VPN or proxy, confirm that it is connected."),
        symbol: "wifi.slash"
    )
    static let timedOut = NavigationError(
        tag: 1,
        name: "timedOut",
        code: "CREST_TIMED_OUT",
        title: LocalizedStringResource("This site took too long to respond"),
        message: LocalizedStringResource("%@ didn’t respond in time."),
        primarySuggestion: LocalizedStringResource("Check your connection and try again in a moment."),
        secondarySuggestion: LocalizedStringResource("If you use a VPN or proxy, confirm that it is connected."),
        symbol: "clock.badge.exclamationmark"
    )
    static let cannotFindServer = NavigationError(
        tag: 2,
        name: "cannotFindServer",
        code: "CREST_NAME_NOT_RESOLVED",
        title: LocalizedStringResource("Server not found"),
        message: LocalizedStringResource("Crest couldn’t find the server for %@."),
        primarySuggestion: LocalizedStringResource("Check the address for typing mistakes."),
        secondarySuggestion: LocalizedStringResource("If the address is correct, check your DNS or VPN settings."),
        symbol: "network.slash"
    )
    static let cannotConnect = NavigationError(
        tag: 3,
        name: "cannotConnect",
        code: "CREST_CONNECTION_REFUSED",
        title: LocalizedStringResource("This site can’t be reached"),
        message: LocalizedStringResource("%@ refused the connection or isn’t accepting connections."),
        primarySuggestion: LocalizedStringResource("Check whether the site is available in another browser or device."),
        secondarySuggestion: LocalizedStringResource(
            "For an intranet site, confirm that you are on the required network."),
        symbol: "exclamationmark.icloud"
    )
    static let connectionLost = NavigationError(
        tag: 4,
        name: "connectionLost",
        code: "CREST_CONNECTION_RESET",
        title: LocalizedStringResource("The connection was interrupted"),
        message: LocalizedStringResource("The connection to %@ ended before the page finished loading."),
        primarySuggestion: LocalizedStringResource("Check your connection and try again in a moment."),
        secondarySuggestion: LocalizedStringResource("If you use a VPN or proxy, confirm that it is connected."),
        symbol: "bolt.horizontal.icloud"
    )
    static let secureConnectionFailed = NavigationError(
        tag: 5,
        name: "secureConnectionFailed",
        code: "CREST_CERTIFICATE_INVALID",
        title: LocalizedStringResource("A secure connection couldn’t be made"),
        message: LocalizedStringResource("Crest couldn’t verify a private, secure connection to %@."),
        primarySuggestion: LocalizedStringResource("Check that your device’s date and time are correct."),
        secondarySuggestion: LocalizedStringResource(
            "Avoid entering private information until the site fixes its certificate."),
        symbol: "lock.trianglebadge.exclamationmark"
    )
    static let tooManyRedirects = NavigationError(
        tag: 6,
        name: "tooManyRedirects",
        code: "CREST_TOO_MANY_REDIRECTS",
        title: LocalizedStringResource("This page is redirecting incorrectly"),
        message: LocalizedStringResource("%@ sent Crest through too many redirects."),
        primarySuggestion: LocalizedStringResource("Try again later; the site may be temporarily misconfigured."),
        secondarySuggestion: LocalizedStringResource("Opening the site’s home page may avoid the redirect loop."),
        symbol: "arrow.trianglehead.2.clockwise.rotate.90"
    )
    static let unsupportedAddress = NavigationError(
        tag: 7,
        name: "unsupportedAddress",
        code: "CREST_UNSUPPORTED_ADDRESS",
        title: LocalizedStringResource("Crest can’t open this address"),
        message: LocalizedStringResource("The address uses a format or protocol Crest doesn’t support."),
        primarySuggestion: LocalizedStringResource("Check the address for typing mistakes."),
        secondarySuggestion: LocalizedStringResource("Try an address beginning with http:// or https://."),
        symbol: "link.badge.plus"
    )
    static let blocked = NavigationError(
        tag: 8,
        name: "blocked",
        code: "CREST_CONTENT_BLOCKED",
        title: LocalizedStringResource("This page was blocked"),
        message: LocalizedStringResource("A security or content policy prevented this page from loading."),
        primarySuggestion: LocalizedStringResource("Review this Space’s content and network settings."),
        secondarySuggestion: LocalizedStringResource("A firewall, filter, or device policy may also be responsible."),
        symbol: "hand.raised.slash"
    )
    static let unavailable = NavigationError(
        tag: 9,
        name: "unavailable",
        code: "CREST_RESOURCE_UNAVAILABLE",
        title: LocalizedStringResource("This page isn’t available"),
        message: LocalizedStringResource("%@ returned a response Crest couldn’t load."),
        primarySuggestion: LocalizedStringResource("Check whether the site is available in another browser or device."),
        secondarySuggestion: LocalizedStringResource(
            "For an intranet site, confirm that you are on the required network."),
        symbol: "exclamationmark.icloud"
    )
    static let webContentProcessStopped = NavigationError(
        tag: 10,
        name: "webContentProcessStopped",
        code: "CREST_WEB_PROCESS_STOPPED",
        title: LocalizedStringResource("This page stopped responding"),
        message: LocalizedStringResource("The web content process stopped repeatedly. Your tab and address are safe."),
        primarySuggestion: LocalizedStringResource("Try reloading the page in a fresh web content process."),
        secondarySuggestion: LocalizedStringResource("If it happens again, try closing and reopening the tab."),
        symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
    )
    static let unknown = NavigationError(
        tag: 11,
        name: "unknown",
        code: "CREST_NAVIGATION_FAILED",
        title: LocalizedStringResource("This page couldn’t be opened"),
        message: LocalizedStringResource("Crest encountered an unexpected problem while opening %@."),
        primarySuggestion: LocalizedStringResource("Try the address again or open a different page."),
        secondarySuggestion: LocalizedStringResource("The technical details below can help identify the cause."),
        symbol: "doc.badge.ellipsis"
    )

    static let all: [NavigationError] = [
        offline,
        timedOut,
        cannotFindServer,
        cannotConnect,
        connectionLost,
        secureConnectionFailed,
        tooManyRedirects,
        unsupportedAddress,
        blocked,
        unavailable,
        webContentProcessStopped,
        unknown,
    ]

    static func named(_ name: String?) -> NavigationError? {
        all.first { $0.name == name }
    }

    static func == (lhs: NavigationError, rhs: NavigationError) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let code: String
        let title: LocalizedStringResource
        let message: LocalizedStringResource
        let primarySuggestion: LocalizedStringResource
        let secondarySuggestion: LocalizedStringResource
        let symbol: String

        init(
            name: String,
            code: String,
            title: LocalizedStringResource,
            message: LocalizedStringResource,
            primarySuggestion: LocalizedStringResource,
            secondarySuggestion: LocalizedStringResource,
            symbol: String
        ) {
            self.name = name
            self.code = code
            self.title = title
            self.message = message
            self.primarySuggestion = primarySuggestion
            self.secondarySuggestion = secondarySuggestion
            self.symbol = symbol
        }
    }
}

struct MemoryPressureLevel: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var severity: Int { facts.severity }
    private let facts: Facts

    private init(tag: Int, name: String, severity: Int) {
        self.tag = tag
        facts = Facts(name: name, severity: severity)
    }

    static let warning = MemoryPressureLevel(tag: 0, name: "warning", severity: 1)
    static let critical = MemoryPressureLevel(tag: 1, name: "critical", severity: 2)

    static let all: [MemoryPressureLevel] = [warning, critical]

    static func named(_ name: String?) -> MemoryPressureLevel? {
        all.first { $0.name == name }
    }

    static func == (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let severity: Int

        init(name: String, severity: Int) {
            self.name = name
            self.severity = severity
        }
    }
}

struct EngineCapability: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var isRequired: Bool { facts.isRequired }
    var startsEngineOnDemand: Bool { facts.startsEngineOnDemand }
    private let facts: Facts

    private init(tag: Int, name: String, isRequired: Bool, startsEngineOnDemand: Bool) {
        self.tag = tag
        facts = Facts(name: name, isRequired: isRequired, startsEngineOnDemand: startsEngineOnDemand)
    }

    static let pages = EngineCapability(tag: 0, name: "pages", isRequired: true, startsEngineOnDemand: false)
    static let navigation = EngineCapability(tag: 1, name: "navigation", isRequired: true, startsEngineOnDemand: false)
    static let find = EngineCapability(tag: 2, name: "find", isRequired: false, startsEngineOnDemand: false)
    static let zoom = EngineCapability(tag: 3, name: "zoom", isRequired: false, startsEngineOnDemand: false)
    static let interactionState = EngineCapability(
        tag: 4,
        name: "interaction-state",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let pageResidency = EngineCapability(
        tag: 5,
        name: "page-residency",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let popups = EngineCapability(tag: 6, name: "popups", isRequired: false, startsEngineOnDemand: false)
    static let workspaceProfiles = EngineCapability(
        tag: 7,
        name: "workspace-profiles",
        isRequired: true,
        startsEngineOnDemand: false
    )
    static let workspaceTransfer = EngineCapability(
        tag: 8,
        name: "workspace-transfer",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let profileDeletion = EngineCapability(
        tag: 9,
        name: "profile-deletion",
        isRequired: true,
        startsEngineOnDemand: false
    )
    static let contentBlocking = EngineCapability(
        tag: 10,
        name: "content-blocking",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let downloads = EngineCapability(tag: 11, name: "downloads", isRequired: false, startsEngineOnDemand: false)
    static let permissions = EngineCapability(
        tag: 12,
        name: "permissions",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let reader = EngineCapability(tag: 13, name: "reader", isRequired: false, startsEngineOnDemand: false)
    static let translation = EngineCapability(
        tag: 14,
        name: "translation",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let selectionTranslation = EngineCapability(
        tag: 15,
        name: "selection-translation",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let localFiles = EngineCapability(
        tag: 16,
        name: "local-files",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let extensions = EngineCapability(tag: 17, name: "extensions", isRequired: false, startsEngineOnDemand: true)
    static let viewportCapture = EngineCapability(
        tag: 18,
        name: "viewport-capture",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let fullPageCapture = EngineCapability(
        tag: 19,
        name: "full-page-capture",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let pdf = EngineCapability(tag: 20, name: "pdf", isRequired: false, startsEngineOnDemand: false)
    static let webArchive = EngineCapability(
        tag: 21,
        name: "web-archive",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let print = EngineCapability(tag: 22, name: "print", isRequired: false, startsEngineOnDemand: false)
    static let inspector = EngineCapability(tag: 23, name: "inspector", isRequired: false, startsEngineOnDemand: false)
    static let featureFlags = EngineCapability(
        tag: 24,
        name: "feature-flags",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let beforeUnload = EngineCapability(
        tag: 25,
        name: "before-unload",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let internalPages = EngineCapability(
        tag: 26,
        name: "internal-pages",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let protectedMedia = EngineCapability(
        tag: 27,
        name: "protected-media",
        isRequired: false,
        startsEngineOnDemand: false
    )
    static let audioSpectrum = EngineCapability(
        tag: 28,
        name: "audio-spectrum",
        isRequired: false,
        startsEngineOnDemand: false
    )

    static let all: [EngineCapability] = [
        pages,
        navigation,
        find,
        zoom,
        interactionState,
        pageResidency,
        popups,
        workspaceProfiles,
        workspaceTransfer,
        profileDeletion,
        contentBlocking,
        downloads,
        permissions,
        reader,
        translation,
        selectionTranslation,
        localFiles,
        extensions,
        viewportCapture,
        fullPageCapture,
        pdf,
        webArchive,
        print,
        inspector,
        featureFlags,
        beforeUnload,
        internalPages,
        protectedMedia,
        audioSpectrum,
    ]

    static func named(_ name: String?) -> EngineCapability? {
        all.first { $0.name == name }
    }

    static func == (lhs: EngineCapability, rhs: EngineCapability) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let isRequired: Bool
        let startsEngineOnDemand: Bool

        init(name: String, isRequired: Bool, startsEngineOnDemand: Bool) {
            self.name = name
            self.isRequired = isRequired
            self.startsEngineOnDemand = startsEngineOnDemand
        }
    }
}

struct EngineRoster: Equatable, Sendable {
    static let unregistered = EngineRoster(
        offered: [
            EngineCapability.pages,
            EngineCapability.navigation,
            EngineCapability.find,
            EngineCapability.zoom,
            EngineCapability.interactionState,
            EngineCapability.pageResidency,
            EngineCapability.popups,
            EngineCapability.workspaceProfiles,
            EngineCapability.workspaceTransfer,
            EngineCapability.profileDeletion,
            EngineCapability.contentBlocking,
            EngineCapability.downloads,
            EngineCapability.permissions,
            EngineCapability.reader,
            EngineCapability.translation,
            EngineCapability.selectionTranslation,
            EngineCapability.localFiles,
            EngineCapability.extensions,
            EngineCapability.viewportCapture,
            EngineCapability.fullPageCapture,
            EngineCapability.pdf,
            EngineCapability.webArchive,
            EngineCapability.print,
            EngineCapability.inspector,
            EngineCapability.featureFlags,
            EngineCapability.beforeUnload,
            EngineCapability.internalPages,
            EngineCapability.protectedMedia,
            EngineCapability.audioSpectrum,
        ]
    )

    let offered: [EngineCapability]
}

struct CapabilityStatus: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var isAvailable: Bool { facts.isAvailable }
    private let facts: Facts

    private init(tag: Int, name: String, isAvailable: Bool) {
        self.tag = tag
        facts = Facts(name: name, isAvailable: isAvailable)
    }

    static let supported = CapabilityStatus(tag: 0, name: "supported", isAvailable: true)
    static let partial = CapabilityStatus(tag: 1, name: "partial", isAvailable: false)
    static let unavailable = CapabilityStatus(tag: 2, name: "unavailable", isAvailable: false)
    static let unverified = CapabilityStatus(tag: 3, name: "unverified", isAvailable: false)

    static let all: [CapabilityStatus] = [supported, partial, unavailable, unverified]

    static func named(_ name: String?) -> CapabilityStatus? {
        all.first { $0.name == name }
    }

    static func == (lhs: CapabilityStatus, rhs: CapabilityStatus) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let isAvailable: Bool

        init(name: String, isAvailable: Bool) {
            self.name = name
            self.isAvailable = isAvailable
        }
    }
}

struct CanReturnToSavedAddress: Equatable, Sendable {
    let workspaceID: UUID
    let windowID: UUID
    let spaceID: UUID
    let tabID: UUID
}

struct PageHistoryEntries: Equatable, Sendable {
    let pageID: UUID
}

struct IdlePages: Equatable, Sendable {
}

struct ArchivedPageHistory: Equatable, Sendable {
    let pageID: UUID
}

struct LinkGesture: Equatable, Sendable {
    var userActivated: Bool
    var topLevel: Bool
    var modifiers: ShortcutModifiers
    var middleClick: Bool
}

struct LinkActivation: Equatable, Sendable {
    let pageID: UUID
    let url: String
    let gesture: LinkGesture
}

struct LinkNavigation: Equatable, Sendable {
    let pageID: UUID
    let url: String?
    let gesture: LinkGesture
}

struct LinkNavigationAnswer: Equatable, Sendable {
    let decision: LinkNavigationDecision
}

struct LinkNavigationDecision: Hashable, Sendable {
    let tag: Int
    var name: String { facts.name }
    var opensTab: Bool { facts.opensTab }
    var selectsTab: Bool { facts.selectsTab }
    private let facts: Facts

    private init(tag: Int, name: String, opensTab: Bool, selectsTab: Bool) {
        self.tag = tag
        facts = Facts(name: name, opensTab: opensTab, selectsTab: selectsTab)
    }

    static let navigate = LinkNavigationDecision(tag: 0, name: "navigate", opensTab: false, selectsTab: false)
    static let backgroundTab = LinkNavigationDecision(tag: 1, name: "backgroundTab", opensTab: true, selectsTab: false)
    static let foregroundTab = LinkNavigationDecision(tag: 2, name: "foregroundTab", opensTab: true, selectsTab: true)

    static let all: [LinkNavigationDecision] = [navigate, backgroundTab, foregroundTab]

    static func named(_ name: String?) -> LinkNavigationDecision? {
        all.first { $0.name == name }
    }

    static func == (lhs: LinkNavigationDecision, rhs: LinkNavigationDecision) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    private final class Facts: Sendable {
        let name: String
        let opensTab: Bool
        let selectsTab: Bool

        init(name: String, opensTab: Bool, selectsTab: Bool) {
            self.name = name
            self.opensTab = opensTab
            self.selectsTab = selectsTab
        }
    }
}

struct ShortcutModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let command = ShortcutModifiers(rawValue: 1)
    static let option = ShortcutModifiers(rawValue: 2)
    static let control = ShortcutModifiers(rawValue: 4)
    static let shift = ShortcutModifiers(rawValue: 8)
}

enum EngineCommand: Equatable, Sendable {
    case adoptOfferedPage(AdoptOfferedPage)
    case closePage(ClosePage)
    case createPage(CreatePage)
    case exitPictureInPicture(ExitPictureInPicture)
    case goToHistoryEntry(GoToHistoryEntry)
    case loadPage(LoadPage)
    case recoverPage(RecoverPage)
    case rejectOfferedPage(RejectOfferedPage)
    case dropStagedLink(DropStagedLink)
    case stageNavigation(StageNavigation)
}
