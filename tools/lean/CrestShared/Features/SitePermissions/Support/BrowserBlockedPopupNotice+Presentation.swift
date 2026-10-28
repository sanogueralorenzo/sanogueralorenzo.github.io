import Foundation

extension BrowserBlockedPopupNotice {
    /// The generator cannot yet carry a string argument on a set's text, so
    /// the title that names the host stays here.
    var title: String {
        status.offersAllow
            ? String(localized: "Pop-up blocked for \(origin.host)")
            : String(localized: "Pop-ups allowed for \(origin.host)")
    }

    var guidance: String {
        String(localized: status.guidance)
    }

    var allowActionAccessibilityLabel: String {
        String(localized: "Allow automatic pop-ups for \(origin.host)")
    }

    var allowActionAccessibilityHint: String {
        String(
            localized:
                "Saves this permission in the current Space. Retry the action on the site afterward"
        )
    }

    func chromeAccessibilityLabel(surfaceName: String) -> String {
        "\(title). \(surfaceName)"
    }
}
