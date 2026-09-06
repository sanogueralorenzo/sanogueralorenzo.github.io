import AppKit

// The same native overlapping-documents symbol used in the menu.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 210, yRadius: 210)
    NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.15, alpha: 1).setFill(); background.fill()
    let tint = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.94, alpha: 1)
    let symbol = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(paletteColors: [tint]))!
    let height: CGFloat = 580
    let width = height * symbol.size.width / symbol.size.height
    symbol.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
    image.unlockFocus()
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render Palette icon") }
    // iconutil expects both standard and Retina variants.
    if size <= 512 { try png.write(to: output.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try png.write(to: output.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
