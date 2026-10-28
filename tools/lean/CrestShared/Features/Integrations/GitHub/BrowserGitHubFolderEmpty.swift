import SwiftUI

/// Connection and empty results belong inside the live folder's disclosure.
struct BrowserGitHubFolderEmpty: View {
    // MARK: - Variables

    @Environment(BrowserGitHubIntegration.self) private var github: BrowserGitHubIntegration?

    // MARK: - Actions - Presentation

    var body: some View {
        Group {
            if let github {
                if github.isLoading {
                    ProgressView().controlSize(.small)
                } else if github.failure == .noFilters {
                    Text("Filter is not set").foregroundStyle(.secondary)
                } else if github.hasRefreshed, github.failure == nil {
                    Text("No open pull requests").foregroundStyle(.secondary)
                } else {
                    Button(
                        github.failure == nil || github.failure == .notSignedIn ? "Connect GitHub" : "Retry",
                        action: {
                            if github.failure == nil || github.failure == .notSignedIn {
                                github.requestConnection()
                            } else {
                                github.requestRefresh()
                            }
                        }
                    )
                    .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
                }
            }
        }
        .font(CrestTypography.metadata)
        .padding(CrestSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
