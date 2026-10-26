import Foundation

extension AutomaticDownloadCheck {
    // MARK: - Variables

    /// The automatic-download action and the page/origin throttle state to
    /// keep. An unavailable core asks the person instead of deciding silently.
    var verdict: AutomaticDownloadVerdict {
        (try? CrestCore.answer(self))
            ?? AutomaticDownloadVerdict(
                action: .requestPermission, hasAllowedAutomaticDownload: hasAllowedAutomaticDownload)
    }
}
