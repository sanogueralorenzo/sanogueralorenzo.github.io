import Foundation

struct BrowserLinkHoverMessage {
    let document: String
    let sequence: Int
    let href: String?

    init?(body: Any) {
        guard let body = body as? [String: Any],
            body.count == 4, body["version"] as? Int == 1,
            let document = body["document"] as? String,
            !document.isEmpty, document.utf8.count <= 128,
            let sequence = body["sequence"] as? Int, sequence > 0,
            let raw = body["href"], raw is String || raw is NSNull
        else { return nil }
        let href = raw as? String
        if let href, href.utf8.count > 8_192 { return nil }
        self.document = document
        self.sequence = sequence
        self.href = href
    }
}
