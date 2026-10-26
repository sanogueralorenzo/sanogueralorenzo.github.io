import Foundation

/// The platform's page hosting what WebKit's binding built: it shows the
/// person the core's questions about the page, gets ready for each load the
/// binding runs in the page, and asks WebKit what media the page runs when
/// that may have changed.
@MainActor
protocol WebKitPageHosting: BrowserPromptPresenting {
    /// The binding is about to load `url` in the page as the app's own load,
    /// or to bring the page's history back there: the page shows itself
    /// heading to `url`, and lets that navigation reach what only the app may
    /// load.
    func prepareToLoad(_ url: URL)

    /// Media in the page started, stopped or ended, so the page asks WebKit
    /// what it runs now and tells the core when that changed.
    func mediaActivityMayHaveChanged()

    /// The core asked for a history entry WebKit no longer keeps, so the page
    /// reports its history again, as WebKit keeps it now.
    func historyMayHaveChanged()
}
