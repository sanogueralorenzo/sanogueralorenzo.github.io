import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Vector sources are bundled. Only the small favicon payload is rasterized,
/// once per mark, so the practice sidebar exercises the real favicon renderer.
@MainActor
enum BrowserGettingStartedArtwork {
    private static var payloads: [String: Data] = [:]

    static func favicon(_ asset: String) -> Data? {
        if let cached = payloads[asset] { return cached }
        let renderer = ImageRenderer(content: Image(asset).resizable().scaledToFit().frame(width: 64, height: 64))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        payloads[asset] = data as Data
        return data as Data
    }
}
