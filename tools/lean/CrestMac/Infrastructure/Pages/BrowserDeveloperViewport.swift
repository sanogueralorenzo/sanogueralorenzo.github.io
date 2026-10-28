import CoreGraphics
import Foundation

/// CSS viewport presets, not hardware or user-agent emulation.
struct BrowserDeveloperViewport: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let compactPhone = BrowserDeveloperViewport(
        name: "compactPhone", title: "Compact Phone", symbol: "iphone", width: 375, height: 667)
    static let phone = BrowserDeveloperViewport(
        name: "phone", title: "Phone", symbol: "iphone", width: 390, height: 844)
    static let largePhone = BrowserDeveloperViewport(
        name: "largePhone", title: "Large Phone", symbol: "iphone", width: 430, height: 932)
    static let desktop = BrowserDeveloperViewport(
        name: "desktop", title: "Desktop", symbol: "laptopcomputer", width: 1280, height: 800)
    static let wideDesktop = BrowserDeveloperViewport(
        name: "wideDesktop", title: "Wide Desktop", symbol: "display", width: 1920, height: 1080)
    static let ultrawide = BrowserDeveloperViewport(
        name: "ultrawide", title: "Ultrawide", symbol: "display", width: 2560, height: 1080)

    /// Every preset, smallest first.
    static let presets: [BrowserDeveloperViewport] = [
        compactPhone, phone, largePhone, desktop, wideDesktop, ultrawide,
    ]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String
    let size: CGSize

    /// Whether the person typed the size in rather than choosing a preset.
    let isCustom: Bool

    var id: String { name }

    var dimensions: String { "\(Int(size.width)) × \(Int(size.height))" }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, width: Int, height: Int, isCustom: Bool = false
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.size = CGSize(width: width, height: height)
        self.isCustom = isCustom
    }

    // MARK: - Actions - Building

    static func custom(width: Int, height: Int) -> BrowserDeveloperViewport {
        BrowserDeveloperViewport(
            name: "custom", title: "Custom", symbol: "ruler", width: width, height: height, isCustom: true)
    }

    static func customSize(width: String, height: String) -> BrowserDeveloperViewport? {
        guard let width = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)),
            let height = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...8192).contains(width), (1...8192).contains(height)
        else { return nil }
        return .custom(width: width, height: height)
    }

    // MARK: - Actions - Identity

    /// A custom viewport is equal to another only at the same size.
    static func == (lhs: BrowserDeveloperViewport, rhs: BrowserDeveloperViewport) -> Bool {
        lhs.name == rhs.name && lhs.size == rhs.size
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }
}

/// Preserve the CSS layout size while fitting its presentation into the Space.
/// Preview uses 100% content zoom; only its presentation scales down.
struct BrowserDeveloperViewportLayout {
    let contentSize: CGSize
    let scale: CGFloat

    init(viewport: BrowserDeveloperViewport?, available: CGSize) {
        guard let viewport else {
            contentSize = available
            scale = 1
            return
        }
        contentSize = viewport.size
        scale = max(0, min(1, available.width / contentSize.width, available.height / contentSize.height))
    }
}
