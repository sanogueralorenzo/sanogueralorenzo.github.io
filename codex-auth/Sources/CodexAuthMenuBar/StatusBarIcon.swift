import AppKit
import Foundation

enum StatusBarIcon {
    static func codex(size: CGFloat = 18) -> NSImage {
        guard let url = Bundle.main.url(forResource: "codex", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(named: NSImage.cautionName) ?? NSImage()
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = false
        return image
    }
}
