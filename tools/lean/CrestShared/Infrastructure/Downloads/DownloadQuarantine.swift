import Foundation

struct BrowserDownloadQuarantine {
    let sourceURL: URL?
    let timestamp: Date
    let agentName: String
    let agentBundleIdentifier: String

    init(
        sourceURL: URL?,
        timestamp: Date = .now,
        agentName: String = ProductIdentity.name,
        agentBundleIdentifier: String =
            Bundle.main.bundleIdentifier ?? "com.pauldavis.crest"
    ) {
        self.sourceURL = sourceURL
        self.timestamp = timestamp
        self.agentName = agentName
        self.agentBundleIdentifier = agentBundleIdentifier
    }
}
