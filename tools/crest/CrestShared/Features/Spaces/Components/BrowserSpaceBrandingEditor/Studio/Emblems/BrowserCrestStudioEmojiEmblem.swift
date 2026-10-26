import Foundation

/// An emblem drawn from an emoji.
struct BrowserCrestStudioEmojiEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .emoji(emblem.emoji)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {
        let text = charge.text ?? ""
        if emblem.emoji != text { emblem.emoji = text }
    }
}
