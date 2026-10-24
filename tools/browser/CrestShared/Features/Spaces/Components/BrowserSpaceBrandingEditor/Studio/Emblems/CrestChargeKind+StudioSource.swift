extension CrestChargeKind {
    /// The source the crest studio edits this kind of emblem with.
    @MainActor
    var studioSource: any BrowserCrestStudioEmblemSource {
        switch kind {
        case .heraldic: BrowserCrestStudioHeraldicEmblem()
        case .system: BrowserCrestStudioSystemEmblem()
        case .emoji: BrowserCrestStudioEmojiEmblem()
        case .monogram: BrowserCrestStudioMonogramEmblem()
        case .none: BrowserCrestStudioNoEmblem()
        }
    }
}
