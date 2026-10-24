import Foundation

/// Where the password field that asked for a credential sits inside its own
/// frame's viewport, in CSS pixels.
///
/// This is page-controlled data, so it is validated exactly as narrowly as the
/// rest of `BrowserCredentialFormMessage`: four finite numbers, a positive size,
/// and magnitudes small enough that no arithmetic downstream can overflow. A
/// rect that fails any of those is not a smaller rect — it is no rect at all,
/// and the prompt falls back to the placement it uses when a field never
/// reported one.
///
/// The values stay `Double` rather than becoming a `CGRect` here because this
/// layer only imports Foundation. Turning CSS pixels into a shell's points is
/// the drawing layer's job anyway: it is the only layer that knows the page's
/// zoom.
struct BrowserCredentialFieldRect: Equatable, Sendable, Decodable {
    /// The largest coordinate or size a page may claim. A document can be very
    /// tall, but nothing honest is a million CSS pixels across.
    static let coordinateLimit: Double = 1_000_000

    let x: Double
    let y: Double
    let width: Double
    let height: Double

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try Self.coordinate(.x, in: container)
        let y = try Self.coordinate(.y, in: container)
        let width = try Self.coordinate(.width, in: container)
        let height = try Self.coordinate(.height, in: container)
        guard width > 0, height > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .width, in: container, debugDescription: "A field rect has a positive size.")
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private static func coordinate(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Double {
        let candidate = try container.decode(Double.self, forKey: key)
        guard candidate.isFinite, abs(candidate) <= coordinateLimit else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "A coordinate is finite and bounded.")
        }
        return candidate
    }
}
