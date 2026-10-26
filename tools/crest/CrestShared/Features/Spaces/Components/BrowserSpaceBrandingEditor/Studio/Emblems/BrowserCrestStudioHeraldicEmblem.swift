import Foundation

/// An emblem drawn from Crest's heraldic artwork, found by name.
struct BrowserCrestStudioHeraldicEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .heraldic(emblem.context.value.crest.symbol)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {}
}
