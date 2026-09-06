import AppKit

@main
@MainActor
enum ClipboardFormatsTests {
    static func main() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 {
            for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) }
        }
        let png = bitmap.representation(using: .png, properties: [:])!
        let tiff = bitmap.representation(using: .tiff, properties: [:])!
        for (type, data) in [(NSPasteboard.PasteboardType.png, png), (.tiff, tiff)] {
            pasteboard.clearContents()
            precondition(pasteboard.setData(data, forType: type))
            let clip = try ClipboardSupport.capture(pasteboard, source: nil)!
            precondition(clip.kind == .image && clip.thumbnail != nil)
            pasteboard.clearContents()
            try ClipboardSupport.restore(clip, to: pasteboard)
            precondition(pasteboard.data(forType: type) == data)
        }
        print("PASS: PNG and TIFF restore their original data")

        var legacy = Clip(id: "legacy", kind: .image, content: "Image",
                          thumbnail: "data:image/png;base64," + png.base64EncodedString(), createdAt: 0)
        for representations: [[Clip.Format]]? in [nil, [[Clip.Format(type: "public.png", data: "invalid")]]] {
            legacy.representations = representations
            pasteboard.clearContents()
            precondition(pasteboard.setString("preserve this", forType: .string))
            let changeCount = pasteboard.changeCount
            do {
                try ClipboardSupport.restore(legacy, to: pasteboard)
                preconditionFailure("An image without valid original data must not restore its thumbnail")
            } catch {
                precondition(error.localizedDescription.contains("Copy the original image again"))
                precondition(pasteboard.changeCount == changeCount)
                precondition(pasteboard.string(forType: .string) == "preserve this")
            }
        }
        print("PASS: missing or invalid original image data leaves the clipboard untouched")
    }
}
