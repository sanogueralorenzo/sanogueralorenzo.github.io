import Foundation

enum BrowserNavigationFailurePreviewFixture {
    /// The Indigo accent's legacy colors on a readable diagonal banner.
    static let branding: SpaceBranding = {
        var look = SpaceAccent.indigo.house
        look.colors = ColorPalette(colors: SpaceAccent.indigo.legacyColors)
        look.readabilityFade = SpaceBranding.legacyReadabilityFade
        look.iconStyle = .simpleSymbol
        return look
    }()
    static let offline = makeFailure(
        error: URLError(.notConnectedToInternet),
        replacedDocument: false
    )
    static let certificate = makeFailure(
        error: URLError(.secureConnectionFailed),
        replacedDocument: true
    )

    private static let fallbackURL: URL = {
        guard
            let url = URL(
                string: "crest-preview://navigation.example/failure"
            )
        else {
            preconditionFailure("Navigation failure preview URL is invalid")
        }
        return url
    }()

    private static func makeFailure(
        error: URLError,
        replacedDocument: Bool
    ) -> PageFailure {
        guard
            let failure = PageFailure(
                error: error,
                replacedDocument: replacedDocument,
                fallbackURL: fallbackURL
            )
        else {
            preconditionFailure("Navigation failure preview is invalid")
        }
        return failure
    }
}
