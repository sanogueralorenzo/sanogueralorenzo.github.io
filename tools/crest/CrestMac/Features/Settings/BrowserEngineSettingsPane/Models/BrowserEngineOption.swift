import SwiftUI

// MARK: - Types

struct BrowserEngineBenefit {
    let title: LocalizedStringResource
    let symbol: String
}

/// Describes a selectable engine with its own artwork and capabilities.
struct BrowserEngineOption: Identifiable {
    // MARK: - Static Variables

    static let all: [BrowserEngineOption] = [
        BrowserEngineOption(
            engine: .chromium, logo: "EngineChromium",
            summary: "Built on ungoogled-chromium, with Google integrations removed. Smooth browsing and extensions.",
            benefits: [
                BrowserEngineBenefit(title: "Smooth webpage performance", symbol: "speedometer"),
                BrowserEngineBenefit(title: "Chrome Web Store extensions", symbol: "puzzlepiece.extension"),
                BrowserEngineBenefit(title: "WebKit fallback for protected video", symbol: "play.rectangle"),
            ]),
        BrowserEngineOption(
            engine: .webKit, logo: "EngineWebKit",
            summary: "Apple’s native web engine, with system integration and protected media playback.",
            benefits: [
                BrowserEngineBenefit(title: "Native macOS handling", symbol: "macwindow"),
                BrowserEngineBenefit(title: "FairPlay protected video", symbol: "play.rectangle"),
                BrowserEngineBenefit(title: "Reader Mode", symbol: "doc.text"),
            ]),
    ]

    // MARK: - Variables

    let engine: EngineKind
    let logo: String
    let summary: LocalizedStringResource
    let benefits: [BrowserEngineBenefit]
    var id: EngineKind { engine }
}
