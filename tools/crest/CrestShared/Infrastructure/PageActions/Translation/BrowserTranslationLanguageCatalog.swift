import Foundation
import Observation
import Translation

/// Apple exposes downloaded pairs, not an inventory of individual downloads.
/// Only positive installed results are offered for automatic translation.
@Observable @MainActor
final class BrowserTranslationLanguageCatalog {
    struct Pair: Hashable, Sendable {
        let source: String
        let target: String
    }

    private(set) var installedPairs: Set<Pair> = []
    private(set) var isRefreshing = false
    private(set) var hasChecked = false

    var installedIDs: [String] {
        Set(installedPairs.flatMap { [$0.source, $0.target] }).sorted {
            Self.name($0).localizedStandardCompare(Self.name($1)) == .orderedAscending
        }
    }

    func targets(for source: String) -> [String] {
        installedIDs.filter { installedPairs.contains(Pair(source: source, target: $0)) }
    }

    static func name(_ id: String) -> String { Locale.current.localizedString(forIdentifier: id) ?? id }

    /// Whether the core reads `lhs` and `rhs` as one language.
    nonisolated static func matches(_ lhs: String, _ rhs: String) -> Bool {
        matches(lhs, in: [rhs]).first ?? false
    }

    /// `matches(language, candidate)` for each candidate, in one core call.
    nonisolated static func matches(_ language: String, in candidates: [String]) -> [Bool] {
        (try? CrestCore.answer(LanguagesMatching(language: language, candidates: candidates)))?.matches
            ?? Array(repeating: false, count: candidates.count)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let installed = await Self.loadInstalledPairs()
        guard !Task.isCancelled else { return }
        installedPairs = installed
        hasChecked = true
    }

    private nonisolated static func loadInstalledPairs() async -> Set<Pair> {
        let languages = await BrowserTranslationPreference.languages()
        let ids = languages.all.map(\.minimalIdentifier)
        let candidates = ids.flatMap { source in
            zip(ids, matches(source, in: ids))
                .filter { !$0.1 }
                .map { Pair(source: source, target: $0.0) }
        }
        return await check(candidates, languages: languages)
    }

    private nonisolated static func check(_ pairs: [Pair], languages: BrowserTranslationPreference.Languages) async
        -> Set<Pair>
    {
        await withTaskGroup(of: Set<Pair>.self, returning: Set<Pair>.self) { group in
            let workerCount = min(4, pairs.count)
            for worker in 0..<workerCount {
                group.addTask {
                    guard !Task.isCancelled else { return [] }
                    // Reuse setup while keeping the non-Sendable checkers within one task.
                    let lowLatency = BrowserTranslationPreference.languageAvailability(lowLatency: true)
                    let standard = BrowserTranslationPreference.languageAvailability(lowLatency: false)
                    var installed: Set<Pair> = []
                    for index in stride(from: worker, to: pairs.count, by: workerCount) {
                        guard !Task.isCancelled else { return installed }
                        let pair = pairs[index]
                        let availability =
                            languages.usesLowLatency(from: pair.source, to: pair.target) ? lowLatency : standard
                        let status = await availability.status(
                            from: .init(identifier: pair.source), to: .init(identifier: pair.target))
                        if status == .installed { installed.insert(pair) }
                    }
                    return installed
                }
            }
            var installed: Set<Pair> = []
            for await batch in group {
                installed.formUnion(batch)
            }
            return installed
        }
    }
}
