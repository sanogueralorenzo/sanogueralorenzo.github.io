import Foundation

/// Decodes the shared fields of the desktop drag and mobile touch bridges.
struct BrowserLinkPullMessage {
    private static let protocolVersion = 1
    private static let maximumIdentifierLength = 100
    private static let maximumURLLength = 8192

    let document: String
    let phase: BrowserLinkPullPhase
    private let body: [String: Any]

    init?(_ body: Any, requiresVersion: Bool = false) {
        guard let body = body as? [String: Any],
            !requiresVersion || (body["version"] as? NSNumber)?.intValue == Self.protocolVersion,
            let document = Self.identifier(body["document"]),
            let rawPhase = body["phase"] as? String, let phase = BrowserLinkPullPhase.named(rawPhase)
        else { return nil }
        self.body = body
        self.document = document
        self.phase = phase
    }

    var token: String? { Self.identifier(body["token"]) }
    var label: String? { body["label"] as? String }
    var time: TimeInterval? { number("time") }
    var location: CGPoint? { point(x: "x", y: "y") }
    var origin: CGPoint? { point(x: "originX", y: "originY") }
    var dragOffset: CGPoint? { point(x: "deltaX", y: "deltaY", fallback: 0) }

    var url: URL? {
        guard let href = body["href"] as? String, href.count <= Self.maximumURLLength else { return nil }
        return URL(string: href)
    }

    private static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, value.count <= maximumIdentifierLength else { return nil }
        return value
    }

    private func number(_ key: String, fallback: Double? = nil) -> Double? {
        guard let value = (body[key] as? NSNumber)?.doubleValue ?? fallback, value.isFinite else { return nil }
        return value
    }

    private func point(x: String, y: String, fallback: Double? = nil) -> CGPoint? {
        guard let x = number(x, fallback: fallback), let y = number(y, fallback: fallback) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
