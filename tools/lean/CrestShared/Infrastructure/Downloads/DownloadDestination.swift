import Foundation

enum BrowserDownloadDestination {
    static let maximumFilenameByteCount = 240

    static func availableURL(
        suggestedFilename: String,
        directory: URL,
        fileExists: (URL) -> Bool
    ) -> URL {
        let filename = safeFilename(from: suggestedFilename)
        let path = filename as NSString
        let stem = path.deletingPathExtension
        let pathExtension = path.pathExtension

        var candidate = directory.appendingPathComponent(filename, isDirectory: false)
        var suffix = 1
        while fileExists(candidate) {
            let suffixedName =
                pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            candidate = directory.appendingPathComponent(suffixedName, isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    static func safeFilename(from suggestedFilename: String) -> String {
        let slashNormalized = suggestedFilename.replacingOccurrences(of: "\\", with: "/")
        let lastComponent =
            slashNormalized.split(separator: "/", omittingEmptySubsequences: true).last
            .map(String.init) ?? ""
        let normalized = lastComponent.precomposedStringWithCanonicalMapping
        let filteredScalars = normalized.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            if isDeceptiveOrControl(scalar) { return nil }
            if scalar == "/" || scalar == "\\" || scalar == ":" { return "_" }
            return scalar
        }
        let unsafeEdgeCharacters = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ".")
        )
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: unsafeEdgeCharacters)
        guard !cleaned.isEmpty else {
            return "download"
        }
        return truncateToFilesystemLimit(cleaned)
    }

    private static func isDeceptiveOrControl(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return value < 0x20
            || (0x7F...0x9F).contains(value)
            || value == 0x061C
            || (0x200B...0x200F).contains(value)
            || (0x202A...0x202E).contains(value)
            || (0x2066...0x2069).contains(value)
            || value == 0xFEFF
    }

    private static func truncateToFilesystemLimit(_ filename: String) -> String {
        guard filename.utf8.count > maximumFilenameByteCount else { return filename }
        let path = filename as NSString
        let extensionWithDot = path.pathExtension.isEmpty ? "" : ".\(path.pathExtension)"
        let safeExtension = extensionWithDot.utf8.count <= 32 ? extensionWithDot : ""
        let stem = safeExtension.isEmpty ? filename : path.deletingPathExtension
        let availableStemBytes = maximumFilenameByteCount - safeExtension.utf8.count
        var result = ""
        for character in stem {
            let candidate = result + String(character)
            guard candidate.utf8.count <= availableStemBytes else { break }
            result = candidate
        }
        let trimmedStem = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedStem.isEmpty ? "download" : trimmedStem) + safeExtension
    }
}
