import Foundation

/// Where the platform says a download's file goes: a place it chose, no place
/// because the person cancelled, or no place because the Space's folder is
/// unavailable. Each answer carries what follows from it, both for the core's
/// question about a download's place and for a file the app saves itself.
protocol BrowserPlatformDownloadResolution: Sendable {
    /// Answers the core's question `asked` through `prompts`.
    @MainActor func answer(_ asked: DownloadDestinationAsked, for prompts: BrowserDownloadPrompts)

    /// Lets go of what the answer holds when no one is left to use it.
    func abandon()

    /// Saves `data`, the download `itemID` from `originatingURL`, as the
    /// answer says, through `center`.
    @MainActor func save(_ data: Data, as itemID: UUID, from originatingURL: URL, in center: BrowserDownloadCenter)
}

extension BrowserPlatformDownloadResolution where Self == BrowserDownloadDestinationChosen {
    /// The file goes to `url`; `securityScopedURL` is the folder access the
    /// write needs, when it needs one.
    static func destination(_ url: URL, securityScopedURL: URL?) -> Self {
        BrowserDownloadDestinationChosen(url: url, securityScopedURL: securityScopedURL)
    }
}

extension BrowserPlatformDownloadResolution where Self == BrowserDownloadDestinationCancelled {
    /// The person cancelled choosing a place.
    static var cancelled: Self { BrowserDownloadDestinationCancelled() }
}

extension BrowserPlatformDownloadResolution where Self == BrowserDownloadFolderUnavailable {
    /// The Space's download folder is unavailable.
    static var unavailable: Self { BrowserDownloadFolderUnavailable() }
}
