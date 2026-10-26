import Foundation

// MARK: - Types

/// A trusted primary-pointer activation as Crest's link bridge posts it: the
/// link and where it sits, as fractions of the viewport.
private struct BrowserDownloadActivationMessage: Decodable {
    /// The only kind of message the bridge posts that is an activation.
    enum Kind: String, Decodable {
        case activation
    }

    let version: Int
    let kind: Kind
    let href: String
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
    let touchX: Double
    let touchY: Double
}

/// A trusted primary-pointer activation reported from Crest's private WebKit
/// content world. Only geometry and the already-owned download destination are
/// retained, and only long enough to match the ensuing download callback.
struct BrowserDownloadSourceCapture: Equatable, Sendable {
    let destinationURL: URL
    let normalizedSourceRect: CGRect
    let normalizedTouchPoint: CGPoint

    init(
        destinationURL: URL,
        normalizedSourceRect: CGRect,
        normalizedTouchPoint: CGPoint
    ) {
        self.destinationURL = destinationURL
        let minX = Self.normalized(normalizedSourceRect.minX)
        let minY = Self.normalized(normalizedSourceRect.minY)
        let width = min(Self.normalized(normalizedSourceRect.width), 1 - minX)
        let height = min(Self.normalized(normalizedSourceRect.height), 1 - minY)
        self.normalizedSourceRect = CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
        self.normalizedTouchPoint = CGPoint(
            x: Self.normalized(normalizedTouchPoint.x),
            y: Self.normalized(normalizedTouchPoint.y)
        )
    }

    /// The capture an activation message from the link bridge reports, decoded
    /// once from the script message's body. Anything else the bridge posts,
    /// and any activation that breaks the contract, is not one.
    init?(messageBody: Any) {
        // The bridge posts other messages on this channel too, some of them
        // long; only an activation is worth decoding.
        let activation = BrowserDownloadActivationMessage.Kind.activation.rawValue
        guard (messageBody as? [String: Any])?["kind"] as? String == activation,
            JSONSerialization.isValidJSONObject(messageBody),
            let data = try? JSONSerialization.data(withJSONObject: messageBody),
            let message = try? JSONDecoder().decode(BrowserDownloadActivationMessage.self, from: data),
            message.version == 1,
            message.href.count <= 4_096,
            let destinationURL = URL(string: message.href),
            ExternalWebLink.accepts(destinationURL)
        else { return nil }

        self.init(
            destinationURL: destinationURL,
            normalizedSourceRect: CGRect(
                x: message.minX,
                y: message.minY,
                width: message.width,
                height: message.height
            ),
            normalizedTouchPoint: CGPoint(x: message.touchX, y: message.touchY)
        )
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct BrowserDownloadSourceStore: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let capture: BrowserDownloadSourceCapture
        let uptime: TimeInterval
    }

    private static let maximumEntries = 8

    let maximumAge: TimeInterval
    private var entries: [Entry] = []

    init(maximumAge: TimeInterval = 8) {
        precondition(maximumAge > 0)
        self.maximumAge = maximumAge
    }

    mutating func record(
        _ capture: BrowserDownloadSourceCapture,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        removeExpired(uptime: uptime)
        entries.append(Entry(capture: capture, uptime: uptime))
        entries = Array(entries.suffix(Self.maximumEntries))
    }

    mutating func consume(
        destinationURL: URL?,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadSourceCapture? {
        removeExpired(uptime: uptime)
        guard let destination = destinationURL?.absoluteString,
            let index = entries.firstIndex(where: {
                $0.capture.destinationURL.absoluteString == destination
            })
        else { return nil }
        return entries.remove(at: index).capture
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func removeExpired(uptime: TimeInterval) {
        entries.removeAll { entry in
            let age = uptime - entry.uptime
            return age < 0 || age > maximumAge
        }
    }
}

struct BrowserDownloadFeedbackSource: Equatable, @unchecked Sendable {
    let pointInGlobal: CGPoint
    let windowIdentifier: ObjectIdentifier?
}
