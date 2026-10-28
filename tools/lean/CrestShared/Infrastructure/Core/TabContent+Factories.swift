import Foundation

extension TabContent {
    /// The Start Page, which the core names.
    static let startPage = TabContent(address: nil, view: nil, title: nil)

    /// The page at `url`, called `title` until it reports its own, or by its
    /// host when the core is given no title.
    static func page(_ url: URL, title: String? = nil) -> TabContent {
        TabContent(address: url.absoluteString, view: nil, title: title)
    }

    /// A native view, which titles and draws its tab itself.
    static func view(_ view: NativeView) -> TabContent {
        TabContent(address: nil, view: view, title: nil)
    }
}
