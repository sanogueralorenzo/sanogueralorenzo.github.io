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
            let snapshot = try ClipboardSupport.snapshot(pasteboard, source: nil)!
            pasteboard.clearContents()
            pasteboard.setString("copied while image preparation is pending", forType: .string)
            let clip = try DispatchQueue(label: "clipboard.test.prepare").sync {
                try ClipboardSupport.prepare(snapshot)!
            }
            precondition(clip.kind == .image && clip.thumbnail != nil)
            pasteboard.clearContents()
            try ClipboardSupport.restore(clip, to: pasteboard)
            precondition(pasteboard.data(forType: type) == data)
        }
        print("PASS: PNG and TIFF restore their original data")

        pasteboard.clearContents()
        pasteboard.setString("", forType: .string)
        let richText = NSAttributedString(string: "Rich text fallback")
        pasteboard.setData(try richText.data(from: NSRange(location: 0, length: richText.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        let richSnapshot = try ClipboardSupport.snapshot(pasteboard, source: nil)!
        let richClip = try ClipboardSupport.prepare(richSnapshot)
        precondition(richClip?.content == "Rich text fallback")
        print("PASS: empty plain text still falls back to RTF")

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

        var link = Clip(id: "link", kind: .url, content: " https://example.com/path?q=hello#section\n", createdAt: 0)
        precondition(link.webURL?.absoluteString == "https://example.com/path?q=hello#section")
        precondition(link.spaceHint == "Space to Open")
        for content in ["file:///tmp/example.png", "javascript:alert(1)", "https://", "https://example.com/two words"] {
            link.content = content
            precondition(link.webURL == nil && link.spaceHint == nil)
        }
        let text = Clip(id: "text", kind: .text, content: "hello", createdAt: 0)
        let imageFile = Clip(id: "file", kind: .file, content: "/tmp/example.png", createdAt: 0)
        let document = Clip(id: "document", kind: .file, content: "/tmp/example.txt", createdAt: 0)
        precondition(text.spaceHint == nil && document.spaceHint == nil)
        precondition(legacy.spaceHint == "Space to Preview" && imageFile.spaceHint == "Space to Preview")
        print("PASS: hover hints and Space actions match images, web links, and other clips")
    }
}
