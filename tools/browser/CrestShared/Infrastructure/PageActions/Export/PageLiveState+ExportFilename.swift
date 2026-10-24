import Foundation

extension PageLiveState {
    // MARK: - Actions - Export

    /// The name a save panel proposes for this document exported with
    /// `pathExtension`: its title, else its host, else "Web Page", made safe
    /// for a file name.
    func suggestedFilename(pathExtension: String) -> String {
        let source =
            Self.normalized(title)
            ?? Self.normalized(documentURL?.host())
            ?? "Web Page"
        var candidate = source.replacingOccurrences(
            of: #"[\x00-\x1F\x7F/\\:*?"<>|]+"#,
            with: "-",
            options: .regularExpression
        )
        candidate =
            candidate
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while candidate.hasSuffix(".") {
            candidate.removeLast()
        }
        let suffix = ".\(pathExtension.lowercased())"
        if candidate.lowercased().hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        candidate = String(candidate.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(candidate.isEmpty ? "Web Page" : candidate).\(pathExtension)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
