import Foundation

/// Keeps the picker grants alive while WebKit asynchronously hands selected
/// paths to its network and content processes. Opening the file in Crest also
/// lets macOS request protected-folder consent before the upload is submitted.
@MainActor
final class BrowserFileUploadAccess {
    typealias Start = @MainActor (URL) -> Bool
    typealias Stop = @MainActor (URL) -> Void
    typealias Validate = @MainActor (URL) throws -> Void

    private let start: Start
    private let stop: Stop
    private let validate: Validate
    private var granted: Set<URL> = []

    init(
        start: @escaping Start = { $0.startAccessingSecurityScopedResource() },
        stop: @escaping Stop = { $0.stopAccessingSecurityScopedResource() },
        validate: @escaping Validate = BrowserFileUploadAccess.validateRead
    ) {
        self.start = start
        self.stop = stop
        self.validate = validate
    }

    func prepare(_ urls: [URL]) throws {
        var added: Set<URL> = []
        do {
            for url in urls {
                if !granted.contains(url), !added.contains(url), start(url) {
                    added.insert(url)
                }
                try validate(url)
            }
            granted.formUnion(added)
        } catch {
            added.forEach(stop)
            throw error
        }
    }

    func invalidate() {
        granted.forEach(stop)
        granted.removeAll()
    }

    isolated deinit {
        granted.forEach(stop)
    }

    private static func validateRead(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } else {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
        }
    }
}
