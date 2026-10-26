import Foundation

/// An emblem of one or two letters in a chosen style.
struct BrowserCrestStudioMonogramEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .monogram(emblem.monogram, emblem.monogramStyle)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {
        let text = charge.text ?? ""
        if emblem.monogram != text { emblem.monogram = text }
        emblem.monogramStyle = charge.style ?? .serif
    }
}
