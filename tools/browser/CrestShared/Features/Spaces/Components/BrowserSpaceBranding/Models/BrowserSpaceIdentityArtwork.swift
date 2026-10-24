enum BrowserSpaceIdentityArtwork: Equatable {
    case crest
    case symbol(String)

    init(_ identity: BrowserSpaceIdentity) {
        self =
            identity.branding.iconStyle == .layeredCrest
            ? .crest
            : .symbol(identity.symbol)
    }
}
