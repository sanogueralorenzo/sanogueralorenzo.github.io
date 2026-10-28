import Foundation

struct CertificateChain: Equatable, Sendable {
    let certificates: [Data]
}

struct ContentFrame: Equatable, Sendable, Identifiable {
    let id: String
    let isMainFrame: Bool
    let `protocol`: String
    let host: String
    let port: Int
}

struct ExtensionAction: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let badge: String
    let icon: Data?
    let pinned: Bool
    let enabled: Bool
}

struct ExtensionActionList: Equatable, Sendable {
    let actions: [ExtensionAction]
}

enum ExtensionChange: Int, CaseIterable, Sendable {
    case enable = 0
    case disable = 1
    case remove = 2
    case pin = 3
    case unpin = 4
}

enum InfoBarAnswer: Int, CaseIterable, Sendable {
    case accept = 0
    case cancel = 1
    case dismiss = 2
}

struct InspectorLayout: Equatable, Sendable {
    let inspector: PageArea?
    let page: PageArea?
}

enum InspectorPanel: Int, CaseIterable, Sendable {
    case console = 0
    case elements = 1
    case network = 2
}

struct InstalledExtension: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let icon: Data?
    let enabled: Bool
    let permissions: [String]
    let fromWebStore: Bool
    let optionsURL: String?
}

struct InstalledExtensionList: Equatable, Sendable {
    let extensions: [InstalledExtension]
}

struct InteractionState: Equatable, Sendable {
    let state: Data?
}

struct KeyModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let shift = KeyModifiers(rawValue: 1)
    static let control = KeyModifiers(rawValue: 2)
    static let option = KeyModifiers(rawValue: 4)
    static let command = KeyModifiers(rawValue: 8)
}

enum MediaPlayback: Int, CaseIterable, Sendable {
    case none = 0
    case playing = 1
    case paused = 2
}

struct PageArea: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum PageConsoleLevel: Int, CaseIterable, Sendable {
    case debug = 0
    case log = 1
    case info = 2
    case warning = 3
    case error = 4
}

struct PageConsoleLog: Equatable, Sendable {
    let messages: [PageConsoleMessage]
    let dropped: Int64
}

struct PageConsoleMessage: Equatable, Sendable {
    let sequence: Int64
    let level: PageConsoleLevel
    let text: String
    let source: String?
    let line: Int
    let at: Date
}

enum PageExportFormat: Int, CaseIterable, Sendable {
    case pdf = 0
    case png = 1
    case mhtml = 2
    case webArchive = 3
}

struct PageHeader: Equatable, Sendable {
    let name: String
    let value: String
}

struct PageIconImage: Equatable, Sendable {
    let image: Data?
}

struct PageKey: Equatable, Sendable {
    var key: String
    var code: String
    var keyCode: Int
    var text: String?
}

struct PageMediaState: Equatable, Sendable {
    let activity: PageMediaActivity
}

struct PageNetworkLog: Equatable, Sendable {
    let requests: [PageNetworkRequest]
    let dropped: Int64
}

struct PageNetworkRequest: Equatable, Sendable {
    let sequence: Int64
    let url: String
    let method: String
    let resourceType: String
    let status: Int
    let mimeType: String?
    let requestHeaders: [PageHeader]
    let responseHeaders: [PageHeader]
    let started: Date
    let duration: Double
    let bytes: Int64
    let failure: String?
}

struct PagePoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

enum PageScriptWorld: Int, CaseIterable, Sendable {
    case agent = 0
    case page = 1
}

enum PointerButton: Int, CaseIterable, Sendable {
    case primary = 0
    case secondary = 1
    case middle = 2
}

enum ShareSourceChoice: Int, CaseIterable, Sendable {
    case cancel = 0
    case tab = 1
    case windowOrScreen = 2
}

struct ShareableTab: Equatable, Sendable {
    let pageID: UUID
    let title: String
    let url: String?
    let icon: Data?
}

enum SidePanelRequest: Int, CaseIterable, Sendable {
    case open = 0
    case close = 1
    case toggle = 2
}

enum SidePanelScope: Int, CaseIterable, Sendable {
    case unavailable = 0
    case tab = 1
    case window = 2
}

enum WebNotificationAnswer: Int, CaseIterable, Sendable {
    case clicked = 0
    case declined = 1
}
