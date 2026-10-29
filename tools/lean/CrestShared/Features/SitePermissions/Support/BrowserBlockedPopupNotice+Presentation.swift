import Foundation

extension BrowserBlockedPopupNotice {
    /// The notice names the site whose automatic popup was held back.
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
