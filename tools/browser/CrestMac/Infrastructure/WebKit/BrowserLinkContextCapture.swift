import Foundation

/// The web content a right-click landed on, held for exactly the one
/// web-content context menu that right-click opens.
///
/// macOS `WKUIDelegate` never reports the element under the cursor, so the
/// destination and image source have to come from the page itself. WebKit
/// dispatches the `contextmenu` DOM event in the web content process before
/// that process answers the UI process with the menu's contents, so a report
/// posted from that event always arrives first — no hit test of Crest's own
/// races WebKit's.
///
/// What such a capture must never do is outlive its menu. A right-click on
/// plain text would otherwise inherit the content from the previous
/// right-click,
/// and "Open Link in Split View" would open a page nobody pointed at. Three
/// rules together make that impossible: every report replaces the slot — a
/// right-click that found no link reports exactly that — a menu *takes* the
/// capture instead of reading it, and a token that only ever increases refuses
/// a second take of the same report even if a caller forgets to clear.
struct BrowserLinkContextCapture: Equatable, Sendable {
    /// The message contract the injected script posts against. A payload from
    /// an older or newer script is discarded rather than guessed at.
    static let contractVersion = 3

    /// Long enough for any real link, short enough that a page cannot park a
    /// megabyte-scale `data:` URL in the slot on every right-click.
    private static let maximumURLLength = 4_096

    private var pendingContext: BrowserLinkContext?
    private var pendingToken = 0
    private var consumedToken = 0

    /// The link a menu opening right now would carry, without consuming it.
    var pendingLink: URL? {
        pendingContextValue?.linkURL
    }

    var pendingImage: URL? {
        pendingContextValue?.imageURL
    }

    /// Records one `contextmenu` report from the content bridge.
    ///
    /// A malformed payload, a report over plain content, and a destination
    /// Crest would not open in a tab are all the same answer: the slot empties.
    /// Anything else would leave the last good link in place for a menu it has
    /// nothing to do with.
    mutating func record(
        body: Any,
        documentURL: URL? = nil,
        isMainFrame: Bool = true
    ) {
        pendingToken += 1
        pendingContext = Self.context(
            body: body,
            documentURL: documentURL,
            isMainFrame: isMainFrame
        )
    }

    /// Hands the pending content to the menu now opening and empties the slot.
    mutating func take() -> BrowserLinkContext? {
        defer { consumedToken = pendingToken }
        return pendingContextValue
    }

    /// Drops whatever a closing menu did not use, and whatever a right-click
    /// that never produced a menu left behind.
    mutating func clear() {
        consumedToken = pendingToken
        pendingContext = nil
    }

    private var pendingContextValue: BrowserLinkContext? {
        pendingToken > consumedToken ? pendingContext : nil
    }

    private static func context(
        body: Any,
        documentURL: URL?,
        isMainFrame: Bool
    ) -> BrowserLinkContext? {
        guard let dictionary = body as? [String: Any],
            dictionary["version"] as? Int == contractVersion,
            let href = dictionary["href"],
            href is String || href is NSNull,
            let imageURL = dictionary["imageURL"],
            imageURL is String || imageURL is NSNull,
            let selectionText = dictionary["selectionText"],
            selectionText is String || selectionText is NSNull,
            let isEditable = dictionary["editable"] as? Bool
        else { return nil }

        let sourceValue: Any = dictionary["sourceURL"] ?? imageURL
        guard sourceValue is String || sourceValue is NSNull else { return nil }
        let encodedMediaType: Any?
        if let explicitMediaType = dictionary["mediaType"] {
            encodedMediaType = explicitMediaType
        } else if imageURL is String {
            encodedMediaType = "image"
        } else {
            encodedMediaType = nil
        }
        let mediaType: BrowserContextMenuMediaType?
        if let encodedMediaType = encodedMediaType as? String {
            guard
                let parsedMediaType = BrowserContextMenuMediaType(
                    rawValue: encodedMediaType
                )
            else { return nil }
            mediaType = parsedMediaType
        } else if encodedMediaType == nil || encodedMediaType is NSNull {
            mediaType = nil
        } else {
            return nil
        }

        return BrowserLinkContext(
            linkURL: webDestination(href),
            sourceURL: mediaSource(sourceValue),
            mediaType: mediaType,
            documentURL: documentURL,
            selectionText: selection(selectionText),
            isEditable: isEditable,
            isMainFrame: isMainFrame
        )
    }

    private static func webDestination(_ value: Any?) -> URL? {
        guard let string = value as? String,
            string.count <= maximumURLLength,
            let url = URL(string: string),
            // The same gate every other link affordance uses, so the menu can
            // never offer a `javascript:` or `data:` destination that the
            // new-tab path would refuse a moment later.
            ExternalWebLink.accepts(url)
        else { return nil }
        return url
    }

    private static func mediaSource(_ value: Any?) -> URL? {
        guard let string = value as? String,
            string.count <= maximumURLLength,
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            ["http", "https", "blob", "data"].contains(scheme)
        else { return nil }
        if ["http", "https"].contains(scheme), url.host?.isEmpty != false {
            return nil
        }
        return url
    }

    private static func selection(_ value: Any?) -> String? {
        guard let value = value as? String,
            !value.isEmpty,
            value.count <= 4_096
        else { return nil }
        return value
    }
}

struct BrowserLinkContext: Equatable, Sendable {
    let linkURL: URL?
    let sourceURL: URL?
    let mediaType: BrowserContextMenuMediaType?
    let documentURL: URL?
    let selectionText: String?
    let isEditable: Bool
    let isMainFrame: Bool

    var imageURL: URL? {
        mediaType == .image ? sourceURL : nil
    }
}

enum BrowserContextMenuMediaType: String, Sendable {
    case image, video, audio
}
