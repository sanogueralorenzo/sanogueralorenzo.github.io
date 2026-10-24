import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit

/// The tab-level operations a page needs from whatever owns it.
@MainActor
protocol BrowserPageHosting: AnyObject {
    /// Lets go of a page its engine closed on its own authority, once the
    /// core closed what owned it. A tab the core kept, such as one in a locked
    /// Space, loads its page anew when it is shown.
    func releaseEngineClosedPage(_ page: BrowserPage)

    /// Retires an empty surface whose initial navigation became a download:
    /// a transient one closes, and a tab's page asks the core to close it as
    /// its own script would.
    func discardDownloadOnlyPage(_ page: BrowserPage)

    /// Brings the live tab that authored a clicked system notification forward.
    func activateNotificationSourcePage(_ page: BrowserPage)

    /// Routes a message received by a shared popup content controller to the
    /// page whose web view actually authored it.
    func routeHostedWebNotificationMessage(_ message: WKScriptMessage)

    /// Routes a pre-macOS 27 geolocation bridge message from a shared popup
    /// content controller to the page whose web view authored it.
    func routeGeolocationMessage(_ message: WKScriptMessage)

    /// Routes a blocked-popup bridge message from a shared popup content
    /// controller to the page whose web view actually authored it.
    func routeBlockedPopupMessage(_ message: WKScriptMessage)

    /// Routes a Media Session message received through an opener's shared
    /// content controller to the resident page that authored it.
    func routeMediaSessionMessage(_ message: WKScriptMessage)
}
