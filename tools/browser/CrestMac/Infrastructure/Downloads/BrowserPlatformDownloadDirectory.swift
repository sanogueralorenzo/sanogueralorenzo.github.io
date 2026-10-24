import AppKit
import Foundation

@MainActor
enum BrowserPlatformDownloadDirectory {
    static func resolve(
        suggestedFilename: String,
        spaceID: UUID,
        forcesPrompt: Bool = false,
        fileManager: FileManager = .default
    ) async -> any BrowserPlatformDownloadResolution {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        let preferences = BrowserPlatformDownloadPreferences.shared
        if forcesPrompt || preferences.asksWhereToSave(for: spaceID) {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = safeFilename
            panel.title = "Save Download"
            panel.prompt = "Save"
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let destination = panel.url else {
                return .cancelled
            }
            return .destination(
                destination,
                securityScopedURL: destination
            )
        }

        if let customDirectory = preferences.directoryURL(for: spaceID) {
            return .destination(
                BrowserDownloadDestination.availableURL(
                    suggestedFilename: safeFilename,
                    directory: customDirectory,
                    fileExists: { fileManager.fileExists(atPath: $0.path) }
                ),
                securityScopedURL: customDirectory
            )
        }
        guard preferences.directoryDisplayName(for: spaceID) == nil else {
            return .unavailable
        }

        guard
            let downloadsDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first
        else { return .unavailable }
        return .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: safeFilename,
                directory: downloadsDirectory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}

@MainActor
final class BrowserPlatformDownloadPreferences {
    static let shared = BrowserPlatformDownloadPreferences()

    private struct VolatileRecord {
        var asksWhereToSave = false
        var bookmark: Data?
        var displayName: String?
    }

    private static let keyPrefix = "browser.download.space."
    private let defaults: UserDefaults?
    private var volatileRecords: [UUID: VolatileRecord] = [:]

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if BrowserLaunchEnvironment.current.requiresIsolation {
            self.defaults = nil
        } else {
            self.defaults = .standard
        }
    }

    func asksWhereToSave(for spaceID: UUID) -> Bool {
        guard let defaults else {
            return volatileRecords[spaceID]?.asksWhereToSave ?? false
        }
        return defaults.bool(forKey: key("asksWhere", for: spaceID))
    }

    func setAsksWhereToSave(_ enabled: Bool, for spaceID: UUID) {
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.asksWhereToSave = enabled
            volatileRecords[spaceID] = record
            return
        }
        defaults.set(enabled, forKey: key("asksWhere", for: spaceID))
    }

    func directoryDisplayName(for spaceID: UUID) -> String? {
        guard let defaults else {
            return volatileRecords[spaceID]?.displayName
        }
        return defaults.string(forKey: key("directoryName", for: spaceID))
    }

    func setDirectoryMetadata(
        bookmark: Data,
        displayName: String,
        for spaceID: UUID
    ) {
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.bookmark = bookmark
            record.displayName = displayName
            volatileRecords[spaceID] = record
            return
        }
        defaults.set(bookmark, forKey: key("directoryBookmark", for: spaceID))
        defaults.set(displayName, forKey: key("directoryName", for: spaceID))
    }

    func rememberDirectory(_ url: URL, for spaceID: UUID) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        setDirectoryMetadata(
            bookmark: bookmark,
            displayName: url.lastPathComponent,
            for: spaceID
        )
    }

    func directoryURL(for spaceID: UUID) -> URL? {
        let bookmark: Data?
        if let defaults {
            bookmark = defaults.data(
                forKey: key("directoryBookmark", for: spaceID)
            )
        } else {
            bookmark = volatileRecords[spaceID]?.bookmark
        }
        guard let bookmark else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
            else {
                return nil
            }
            if isStale {
                try? rememberDirectory(url, for: spaceID)
            }
            return url
        } catch {
            return nil
        }
    }

    func clearDirectory(for spaceID: UUID) {
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.bookmark = nil
            record.displayName = nil
            volatileRecords[spaceID] = record
            return
        }
        defaults.removeObject(forKey: key("directoryBookmark", for: spaceID))
        defaults.removeObject(forKey: key("directoryName", for: spaceID))
    }

    private func key(_ suffix: String, for spaceID: UUID) -> String {
        Self.keyPrefix
            + spaceID.uuidString.lowercased()
            + "."
            + suffix
    }
}
