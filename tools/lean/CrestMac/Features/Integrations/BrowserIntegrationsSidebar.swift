import SwiftUI

/// The Space owns integration state; ordinary folder and tab rows render it.
struct BrowserIntegrationsSidebar<Content: View>: View {
    // MARK: - Variables

    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool
    @ViewBuilder var content: () -> Content
    @State private var github = BrowserGitHubIntegration()

    // MARK: - Actions - Presentation

    var body: some View {
        content()
            .environment(github)
            .background {
                BrowserGitHubSidebar(
                    space: space, browser: browser, pages: pages, integration: github)
            }
    }
}
