import Foundation

/// An immutable view of the window for one answer. Ranking runs off the main
/// actor and never owns or mutates a second browser session.
struct PaletteSpaceSnapshot: Sendable {
    let folders: [FolderState]
    let tabs: [TabState]
    let history: [HistoryEntryState]
}

struct PaletteSpaceChoice: Sendable {
    let id: UUID
    let name: String
}

struct NativePalette: Sendable {
    let space: PaletteSpaceSnapshot?
    let shownTabID: UUID?
    let isPrivate: Bool
    let spaces: [PaletteSpaceChoice]
    let now: Date
    let provider: SearchProvider
    let suggests: Bool
    let resolution: ResolvedAddress?

    private struct Candidate {
        var row: PaletteRow
        let section: PaletteSection
        let score: Int
        let place: String?
        let mayLead: Bool
    }
    private static let sections: [PaletteSection] = [
        .recentTabs, .tabs, .saved, .history, .actions, .spaces, .searchSuggestions,
    ]

    func answer(_ question: PaletteSuggestions) -> PaletteAnswer {
        let query = PaletteQuery(question.text)
        if let scope = question.scope {
            let rows = candidates(query, question: question, section: scope.section, narrowed: true).sorted {
                $0.score > $1.score
            }.prefix(scope.section.scopedLimit).map(\.row)
            return answered(rows.isEmpty ? [] : [PaletteGroup(section: scope.section, rows: rows)])
        }
        let trimmed = question.text.drop(while: \.isWhitespace)
        if let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }),
            let scope = PaletteScope.keyed(String(trimmed[..<split]))
        {
            let text = String(trimmed[trimmed.index(after: split)...].drop(while: \.isWhitespace))
            let nested = answer(
                PaletteSuggestions(
                    windowID: question.windowID, text: text, commands: question.commands,
                    settingsPages: question.settingsPages, remote: [], scope: scope,
                    allowsCompletion: question.allowsCompletion))
            return PaletteAnswer(
                groups: nested.groups, completion: nil, suggestionAddress: nil, offeredScope: nil,
                entry: PaletteEntry(scope: scope, text: text))
        }
        if query.isEmpty { return answered(resting(question)) }
        let completion = completion(question)
        let found = intents(query)
        var ranked = Self.sections.flatMap { candidates(query, question: question, section: $0, narrowed: false) }
        var claimed = Set(
            space?.tabs.compactMap { BrowserWebAddress.place(($0.placement.isDurable ? $0.savedURL : nil) ?? $0.url) }
                ?? [])
        if let place = BrowserWebAddress.place(found.first?.address) { claimed.insert(place) }
        ranked.removeAll { $0.section == .history && $0.place.map(claimed.contains) == true }
        let lead = leading(query, completion: completion, ranked: ranked, completes: question.allowsCompletion)
        if let lead {
            ranked.removeAll { candidate in
                var row = candidate.row
                row.reason = lead.row.reason
                return row == lead.row
            }
        }
        var groups: [PaletteGroup] = lead.map { [PaletteGroup(section: .topHit, rows: [$0.row])] } ?? []
        var intents = found.filter { $0.address != lead?.row.address }
        if query.text.hasPrefix("@") {
            for scope in PaletteScope.all where scope.keyword.lowercased().hasPrefix(query.text.lowercased()) {
                intents.append(
                    .make(.scope, "Search \(scope.englishTitle)", scope.keyword, symbol: scope.symbol, scope: scope))
            }
        }
        if !intents.isEmpty { groups.append(PaletteGroup(section: .intent, rows: intents)) }
        let shown = groups.flatMap(\.rows) + ranked.map(\.row)
        for section in Self.sections where section != .searchSuggestions {
            let rows = ranked.filter { $0.section == section }.sorted { $0.score > $1.score }.prefix(
                max(section.limit, section.restingLimit)
            ).map(\.row)
            if !rows.isEmpty { groups.append(PaletteGroup(section: section, rows: rows)) }
        }
        let suggestions = suggestions(question.text, remote: question.remote, shown: shown)
        if !suggestions.isEmpty { groups.append(PaletteGroup(section: .searchSuggestions, rows: suggestions)) }
        let proposal = completion.map {
            AddressCompletion(
                typed: question.text,
                suffix: String(decoding: $0.text.utf16.dropFirst(question.text.utf16.count), as: UTF16.self),
                accepted: $0.text.contains("://") || $0.candidate.scheme == "https"
                    ? $0.text : "\($0.candidate.scheme)://\($0.text)")
        }
        return PaletteAnswer(
            groups: groups, completion: proposal, suggestionAddress: suggestionAddress(question.text),
            offeredScope: PaletteScope.keyed(query.text), entry: nil)
    }

    private func answered(_ groups: [PaletteGroup]) -> PaletteAnswer {
        PaletteAnswer(groups: groups, completion: nil, suggestionAddress: nil, offeredScope: nil, entry: nil)
    }

    private func resting(_ question: PaletteSuggestions) -> [PaletteGroup] {
        var groups: [PaletteGroup] = []
        let recent = (space?.tabs ?? []).filter { $0.id != shownTabID && $0.surface != .startPage }.sorted {
            $0.lastActivatedAt > $1.lastActivatedAt
        }.prefix(PaletteSection.recentTabs.restingLimit).map {
            PaletteRow.make(
                $0.placement.paletteRow, $0.displayTitle, BrowserWebAddress.host($0.url) ?? $0.url ?? "", tab: $0.id)
        }
        if !recent.isEmpty { groups.append(PaletteGroup(section: .recentTabs, rows: recent)) }
        let commands = question.commands.filter { $0.command.offersInPalette && $0.command.paletteRest != nil }.sorted {
            $0.command.paletteRest! < $1.command.paletteRest!
        }.prefix(PaletteSection.actions.restingLimit).map(commandRow)
        if !commands.isEmpty { groups.append(PaletteGroup(section: .actions, rows: commands)) }
        return groups
    }

    private func commandRow(_ command: PaletteCommand) -> PaletteRow {
        .make(.command, command.title, command.sectionTitle, symbol: command.command.symbol, command: command.command)
    }

    private func candidates(
        _ query: PaletteQuery, question: PaletteSuggestions, section: PaletteSection, narrowed: Bool
    ) -> [Candidate] {
        var rows: [Candidate] = []
        switch section {
        case .tabs, .saved:
            for tab in space?.tabs ?? [] {
                if section == .tabs && (tab.id == shownTabID || tab.surface == .startPage || tab.placement.isDurable) {
                    continue
                }
                if section == .saved && !tab.placement.isDurable { continue }
                let address = (tab.placement.isDurable ? tab.savedURL : nil) ?? tab.url
                let host = BrowserWebAddress.host(address) ?? ""
                let path = tab.folderID.map(folderPath) ?? ""
                let subtitle =
                    section == .tabs
                    ? BrowserWebAddress.host(tab.url) ?? tab.url ?? ""
                    : path.isEmpty ? host : host.isEmpty ? path : "\(path) · \(host)"
                let row = PaletteRow.make(tab.placement.paletteRow, tab.displayTitle, subtitle, tab: tab.id)
                if let candidate = evidence(
                    query, row: row, section: section, title: tab.displayTitle, address: address,
                    lastUsed: tab.lastActivatedAt)
                {
                    rows.append(candidate)
                }
            }
            if section == .saved {
                for folder in orderedFolders() {
                    let tabs = (space?.tabs ?? []).filter { $0.placement.isDurable && $0.folderID == folder.id }
                    guard let first = tabs.first else { continue }
                    let path = folderPath(folder.id)
                    guard let score = query.isEmpty ? 0 : query.score(folder.title, path) else { continue }
                    let count = tabs.count == 1 ? "1 tab" : "\(tabs.count) tabs"
                    let row = PaletteRow.make(
                        .folder, folder.title, path.contains("›") ? "\(path) · \(count)" : count, symbol: "folder",
                        subject: folder.id, tab: first.id, reason: .titleMatch)
                    rows.append(Candidate(row: row, section: section, score: score - 50, place: nil, mayLead: false))
                }
            }
        case .history:
            for entry in (space?.history ?? []).prefix(1_500) {
                let title = entry.title.isEmpty ? BrowserWebAddress.host(entry.url) ?? entry.url : entry.title
                let row = PaletteRow.make(.history, title, entry.url, subject: entry.id, address: entry.url)
                if let candidate = evidence(
                    query, row: row, section: .history, title: title, address: entry.url, entry: entry)
                {
                    rows.append(candidate)
                }
            }
        case .actions:
            if narrowed || query.text.utf16.count >= 2 {
                for command in question.commands where command.command.offersInPalette {
                    guard
                        let score = query.isEmpty
                            ? 0 : query.score(command.title, command.sectionTitle) ?? query.abbreviates(command.title)
                    else { continue }
                    rows.append(
                        Candidate(row: commandRow(command), section: .actions, score: score, place: nil, mayLead: false)
                    )
                }
            }
            if !narrowed, query.text.utf16.count >= 2 {
                for page in question.settingsPages {
                    guard let score = query.score(page.title, page.terms) ?? query.abbreviates(page.title) else {
                        continue
                    }
                    rows.append(
                        Candidate(
                            row: .make(.settingsPage, page.title, "Settings", page: page.name), section: .actions,
                            score: score, place: nil, mayLead: false))
                }
            }
        case .spaces:
            for space in spaces {
                guard
                    let score = query.isEmpty
                        ? 0 : query.score(space.name) ?? query.abbreviates(space.name)
                else { continue }
                rows.append(
                    Candidate(
                        row: .make(.space, space.name, "Space", symbol: "", subject: space.id),
                        section: .spaces, score: score, place: nil, mayLead: false))
            }
        default: break
        }
        return rows
    }

    private func evidence(
        _ query: PaletteQuery, row: PaletteRow, section: PaletteSection, title: String, address: String?,
        lastUsed: Date? = nil, entry: HistoryEntryState? = nil
    ) -> Candidate? {
        let place = BrowserWebAddress.place(address)
        let prefixesTitle = query.prefixes(title)
        let prefixes = prefixesTitle || place.map(query.prefixes) == true
        var score = query.isEmpty ? 0 : query.score(title, place ?? "")
        if prefixes { score = max(score ?? 0, 1_000) }
        guard let matched = score else { return nil }
        let visit =
            entry
            ?? BrowserWebAddress.normalized(address).flatMap { normalized in
                space?.history.first { $0.url == normalized }
            }
        let frecency =
            visit.map {
                Double(max(1, $0.visitCount)) * pow(2, -now.timeIntervalSince($0.lastVisitedAt) / (86_400 * 30))
            } ?? 0
        let usage = Int(min(300, 60 * log2(1 + frecency)))
        let age = lastUsed.map { now.timeIntervalSince($0) }
        let recency =
            age.map { $0 <= 3_600 ? 200 : $0 >= 86_400 ? 0 : Int(200 * (86_400 - $0) / (86_400 - 3_600)) } ?? 0
        let kept = section == .saved ? 100 : 0
        let open = section == .tabs ? 150 : 0
        var row = row
        row.reason =
            (section != .history && recency >= 100)
            ? .recentlyUsed
            : usage >= 120
                ? .oftenVisited : open > 0 ? .openTab : kept > 0 ? .kept : prefixesTitle ? .titleMatch : .addressMatch
        return Candidate(
            row: row, section: section, score: matched + usage + kept + open + (section == .history ? 0 : recency),
            place: place,
            mayLead: prefixes && (usage >= 120 || kept > 0 || open > 0 || section != .history && recency >= 100))
    }

    private func leading(_ query: PaletteQuery, completion: PaletteAddressMatch?, ranked: [Candidate], completes: Bool)
        -> Candidate?
    {
        if let calculation = PaletteCalculation.read(query.text) {
            return Candidate(
                row: .make(.calculation, calculation.answer, "\(calculation.expression) ="), section: .topHit,
                score: .max, place: nil, mayLead: true)
        }
        guard completes else { return nil }
        if let completion {
            let place = BrowserWebAddress.place(completion.opens)
            if var open = ranked.first(where: { $0.place == place && $0.row.tabID != nil }) {
                open.row.reason = .completion
                return open
            }
            let host =
                completion.text.contains("://")
                ? completion.text
                : completion.text.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            return Candidate(
                row: .make(
                    .openAddress, "Open \(host)", completion.opens, address: completion.opens, reason: .completion),
                section: .history, score: .max, place: place, mayLead: true)
        }
        guard query.text.utf16.count >= 2 else { return nil }
        return ranked.filter(\.mayLead).reduce(nil) { best, candidate in
            best == nil || candidate.score > best!.score ? candidate : best
        }
    }

    private func folderPath(_ id: UUID) -> String {
        let byID = Dictionary(uniqueKeysWithValues: (space?.folders ?? []).map { ($0.id, $0) })
        var titles: [String] = []
        var current: UUID? = id
        var seen: Set<UUID> = []
        while let id = current, seen.insert(id).inserted, let folder = byID[id] {
            titles.append(folder.title)
            current = folder.parentID
        }
        return titles.reversed().joined(separator: " › ")
    }
    private func orderedFolders() -> [FolderState] {
        let folders = space?.folders ?? []
        var ordered: [FolderState] = []
        func append(_ parent: UUID?) {
            for folder in folders where folder.parentID == parent {
                ordered.append(folder)
                append(folder.id)
            }
        }
        append(nil)
        return ordered
    }
}

extension PaletteRow {
    static func make(
        _ kind: PaletteRowKind, _ title: String, _ subtitle: String, symbol: String? = nil, subject: UUID? = nil,
        tab: UUID? = nil, address: String? = nil, command: ShortcutCommand? = nil, provider: SearchProvider? = nil,
        page: String? = nil, scope: PaletteScope? = nil, reason: PaletteReason? = nil
    ) -> Self {
        Self(
            kind: kind, title: title, subtitle: subtitle, symbol: symbol ?? kind.symbol, subjectID: subject, tabID: tab,
            address: address, command: command, provider: provider, settingsPage: page, scope: scope, reason: reason)
    }
}
extension TabPlacement {
    var paletteRow: PaletteRowKind { self == .pinned ? .pinnedTab : self == .saved ? .savedTab : .tab }
}
extension PaletteScope {
    static func keyed(_ text: String) -> Self? { all.first { $0.keyword.lowercased() == text.lowercased() } }
    var section: PaletteSection { PaletteSection.named(name)! }
    var englishTitle: String {
        switch self {
        case .tabs: "Tabs"
        case .saved: "Pinned & Saved"
        case .history: "History"
        case .actions: "Actions"
        case .spaces: "Spaces"
        }
    }
}
