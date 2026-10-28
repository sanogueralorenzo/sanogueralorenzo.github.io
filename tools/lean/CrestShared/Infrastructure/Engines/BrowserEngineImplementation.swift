import Foundation

/// The native platform that staged a WebKit navigation.
enum BrowserEngineImplementation: String, Codable, Sendable {
    case webKitMacOS = "crest.webkit.macos"
    case webKitIOS = "crest.webkit.ios"
}
