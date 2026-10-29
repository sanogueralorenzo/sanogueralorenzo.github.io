import Foundation

/// Site capabilities offered by the browser. Names are also the saved permission keys.
struct SitePermission: Hashable, Sendable {
    static let camera = Self(
        name: "camera", title: "Camera", symbol: "video", requestTitle: "Wants to use your camera", isMedia: true,
        isEngineEnforced: true)
    static let microphone = Self(
        name: "microphone", title: "Microphone", symbol: "mic", requestTitle: "Wants to use your microphone",
        isMedia: true, isEngineEnforced: true)
    static let cameraAndMicrophone = Self(
        name: "cameraAndMicrophone", title: "Camera & Microphone", symbol: "video.and.waveform",
        requestTitle: "Wants to use your camera and microphone", isMedia: true, components: [.camera, .microphone])
    static let location = Self(
        name: "location", title: "Location", symbol: "location", requestTitle: "Wants to use your location",
        isEngineEnforced: true)
    static let notifications = Self(
        name: "notifications", title: "Notifications", symbol: "bell", requestTitle: "Wants to send notifications",
        isEngineEnforced: true)
    static let popups = Self(
        name: "popups", title: "Automatic Pop-ups", symbol: "macwindow.on.rectangle",
        requestTitle: "Requests permission", askTitle: "Blocked by Default", askChoiceTitle: "Default (Block)")
    static let automaticDownloads = Self(
        name: "automaticDownloads", title: "Automatic Downloads", symbol: "arrow.down.circle",
        requestTitle: "Wants to download multiple files automatically", askTitle: "Ask after First",
        askChoiceTitle: "Default (Ask after First)")
    static let externalApplications = Self(
        name: "externalApplications", title: "External Apps", symbol: "arrow.up.forward.app",
        requestTitle: "Requests permission")
    static let screenSharing = Self(
        name: "screenSharing", title: "Screen Sharing", symbol: "rectangle.inset.filled.and.person.filled",
        requestTitle: "Wants to share your screen", isAskedBySystem: true)
    static let all = [
        camera, microphone, cameraAndMicrophone, location, notifications, popups, automaticDownloads,
        externalApplications, screenSharing,
    ]

    let name: String
    let title: LocalizedStringResource
    let symbol: String
    let requestTitle: LocalizedStringResource
    let askTitle: LocalizedStringResource
    let askChoiceTitle: LocalizedStringResource
    let isMedia: Bool
    let isEngineEnforced: Bool
    let isAskedBySystem: Bool
    let components: [SitePermission]

    private init(
        name: String, title: LocalizedStringResource, symbol: String, requestTitle: LocalizedStringResource,
        askTitle: LocalizedStringResource = "Ask", askChoiceTitle: LocalizedStringResource = "Ask",
        isMedia: Bool = false, isEngineEnforced: Bool = false, isAskedBySystem: Bool = false,
        components: [SitePermission] = []
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.requestTitle = requestTitle
        self.askTitle = askTitle
        self.askChoiceTitle = askChoiceTitle
        self.isMedia = isMedia
        self.isEngineEnforced = isEngineEnforced
        self.isAskedBySystem = isAskedBySystem
        self.components = components
    }

    static func named(_ name: String?) -> Self? { all.first { $0.name == name } }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
