import Foundation

/// The stable feed for the WebKit product.
struct BrowserSoftwareUpdateFeed {
    static let current = BrowserSoftwareUpdateFeed()
    let url = URL(string: "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-webkit.xml")
}
