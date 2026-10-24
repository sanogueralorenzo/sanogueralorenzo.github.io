import Foundation

actor BrowserFaviconPaletteLoader {
    typealias PaletteProvider = @Sendable (Data) async -> BrowserFaviconPalette?

    static let cacheLimit = 128

    private let maximumCacheEntryCount: Int
    private let paletteProvider: PaletteProvider
    private var cache: [Data: BrowserFaviconPalette] = [:]
    private var cacheOrder: [Data] = []
    private var inFlight: [Data: Task<BrowserFaviconPalette?, Never>] = [:]

    init(
        cacheLimit: Int = BrowserFaviconPaletteLoader.cacheLimit,
        paletteProvider: @escaping PaletteProvider
    ) {
        maximumCacheEntryCount = cacheLimit
        self.paletteProvider = paletteProvider
    }

    func palette(for data: Data) async -> BrowserFaviconPalette? {
        if let cached = cache[data] {
            return cached
        }
        if let task = inFlight[data] {
            return await task.value
        }

        let task = Task { [paletteProvider] in
            await paletteProvider(data)
        }
        inFlight[data] = task
        let palette = await task.value
        inFlight[data] = nil
        if let palette {
            cache[data] = palette
            cacheOrder.append(data)
            while cacheOrder.count > maximumCacheEntryCount {
                cache[cacheOrder.removeFirst()] = nil
            }
        }
        return palette
    }
}
