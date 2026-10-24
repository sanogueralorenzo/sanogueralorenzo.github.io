import Foundation

/// No emblem on the crest.
struct BrowserCrestStudioNoEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        CrestCharge.none
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {}
}
