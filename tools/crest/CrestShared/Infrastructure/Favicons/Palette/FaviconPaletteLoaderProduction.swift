import Foundation

enum BrowserFaviconPaletteLoaderProduction {
    static let shared = BrowserFaviconPaletteLoader { data in
        await Task.detached(priority: .utility) {
            BrowserFaviconPaletteExtractor().palette(imageData: data)
        }.value
    }
}
