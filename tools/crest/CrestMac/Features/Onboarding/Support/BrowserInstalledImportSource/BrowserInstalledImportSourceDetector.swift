import AppKit

@MainActor
enum BrowserInstalledImportSourceDetector {
    /// Each browser Crest imports from that is installed, found by its app
    /// alone. Reading another app's data can make macOS warn that Crest
    /// looked at it, so setup reads none until the person asks.
    static func installedSources(
        workspace: NSWorkspace = .shared
    ) -> [BrowserInstalledImportSource] {
        ImportSource.all.compactMap { application in
            guard
                let url = workspace.urlForApplication(
                    withBundleIdentifier: application.bundleIdentifier
                )
            else { return nil }
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return BrowserInstalledImportSource(application: application, applicationURL: url, icon: icon)
        }
    }

    /// `source` with what the core finds in its data folder.
    static func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        let application = source.application
        return source.detecting(
            BrowserDetectedImportPayload(
                application: application, data: application.importData(in: application.defaultDataDirectory)))
    }

    /// The browsers installed here that Crest does not list, each paired by
    /// the core with the Chromium data it keeps, under the browser's own name
    /// and icon. Every app that opens web links is a candidate; Crest itself
    /// and the browsers it lists are not.
    static func unlistedSources(
        workspace: NSWorkspace = .shared
    ) -> [BrowserInstalledImportSource] {
        guard let link = URL(string: "https://example.com") else { return [] }
        let listed = Set(ImportSource.all.map(\.bundleIdentifier))
        var urls: [String: URL] = [:]
        let apps = workspace.urlsForApplications(toOpen: link).compactMap { url -> ImportBrowserApp? in
            guard let identifier = Bundle(url: url)?.bundleIdentifier,
                !listed.contains(identifier), !identifier.hasPrefix(ProductIdentity.bundleIdentifier),
                urls[identifier] == nil
            else { return nil }
            urls[identifier] = url
            return ImportBrowserApp(
                bundleIdentifier: identifier,
                name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
        guard !apps.isEmpty,
            let found = try? CrestCore.answer(
                FindChromiumBrowsers(home: ImportSource.hostHomeDirectory.path, apps: apps))
        else { return [] }
        return found.compactMap { browser in
            guard let url = urls[browser.bundleIdentifier] else { return nil }
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return BrowserInstalledImportSource(
                application: .otherChromium,
                applicationURL: url,
                detectedPayload: BrowserDetectedImportPayload(application: .otherChromium, data: browser.data),
                icon: icon,
                title: browser.name
            )
        }
    }
}
