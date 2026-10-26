import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Icon Composer exports the face. Add the standard transparent macOS margin
// offline without scaling its pixels, so the app can use the finished icon as-is.
let arguments = CommandLine.arguments
guard arguments.count == 4, let pixels = Int(arguments[3]), [512, 1024].contains(pixels),
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
    let face = CGImageSourceCreateImageAtIndex(source, 0, nil),
    face.width == pixels * 824 / 1024, face.height == face.width,
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let canvas = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("Expected an Icon Composer face and a 512px or 1024px output canvas") }

let inset = (pixels - face.width) / 2
canvas.draw(face, in: CGRect(x: inset, y: inset, width: face.width, height: face.height))
guard let image = canvas.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("Could not create the Mac app icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save the Mac app icon") }
