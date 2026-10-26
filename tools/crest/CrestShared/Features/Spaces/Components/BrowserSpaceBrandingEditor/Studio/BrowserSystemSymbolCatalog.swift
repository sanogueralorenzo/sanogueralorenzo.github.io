import SwiftUI

/// The name catalog is generated from a versioned export, never discovered via
/// private OS bundles. Artwork and availability come from public platform APIs.
@MainActor
enum BrowserSystemSymbolCatalog {
    private static var loading: Task<[String], Never>?

    static func availableNames() async -> [String] {
        if let loading { return await loading.value }
        let task = Task { @MainActor in
            guard let url = Bundle.main.url(forResource: "SFSymbolNames", withExtension: "txt"),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return [String]() }
            let candidates = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            var available: [String] = []
            for (index, name) in candidates.enumerated() {
                let exists: Bool
                #if os(macOS)
                    exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
                #else
                    exists = UIImage(systemName: name) != nil
                #endif
                if exists { available.append(name) }
                if index.isMultiple(of: 100) { await Task.yield() }
            }
            return Array(Set(available)).sorted()
        }
        loading = task
        return await task.value
    }
}
