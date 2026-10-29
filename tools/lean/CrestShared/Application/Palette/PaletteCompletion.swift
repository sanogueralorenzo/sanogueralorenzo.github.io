import Foundation

struct PaletteTypedAddress {
    let text: String
    let schemePrefix: String
    let authority: String
    let path: String?
    let hasColon: Bool

    init?(_ text: String) {
        guard (2...2_048).contains(text.utf16.count), !text.contains(where: \.isWhitespace),
            !text.contains("?"), !text.contains("#"), !text.contains("@")
        else { return nil }
        let lower = text.lowercased()
        let scheme: String
        if text.contains("://") {
            if lower.hasPrefix("https://") {
                scheme = "https://"
            } else if lower.hasPrefix("http://") {
                scheme = "http://"
            } else {
                return nil
            }
        } else {
            scheme = ""
        }
        let rest = String(text.dropFirst(scheme.count))
        guard rest.utf16.count >= 2 else { return nil }
        let slash = rest.firstIndex(of: "/")
        self.text = text
        schemePrefix = scheme
        authority = String(slash.map { rest[..<$0] } ?? rest[...]).lowercased()
        path = slash.map { String(rest[$0...]) }
        hasColon = text.contains(":")
    }
}

struct PaletteAddressCandidate: Sendable {
    let url: String
    let source: Int
    let date: Date
    let visits: Int
    let scheme: String
    let authority: String
    let hasPort: Bool
    let path: String
    let suffix: String

    init?(_ url: String, source: Int, date: Date, visits: Int = 0) {
        guard URL(string: url) != nil, let separator = url.range(of: "://") else { return nil }
        let scheme = url[..<separator.lowerBound].lowercased()
        guard scheme == "https" || scheme == "http" else { return nil }
        let rest = url[separator.upperBound...]
        let end = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let authority = String(rest[..<end])
        guard !authority.isEmpty, !authority.contains("@") else { return nil }
        let port =
            authority.hasPrefix("[")
            ? authority.range(of: "]:")?.upperBound : authority.lastIndex(of: ":").map { authority.index(after: $0) }
        let hasPort = port.map { $0 < authority.endIndex } ?? false
        let remainder = rest[end...]
        let suffix = remainder.firstIndex(where: { "?#".contains($0) }) ?? remainder.endIndex
        self.url = url
        self.source = source
        self.date = date
        self.visits = min(20, visits)
        self.scheme = scheme
        self.authority = authority
        self.hasPort = hasPort
        path = String(remainder[..<suffix])
        self.suffix = String(remainder[suffix...])
    }

    func completing(_ typed: PaletteTypedAddress) -> PaletteAddressMatch? {
        guard typed.schemePrefix.isEmpty || typed.schemePrefix == scheme + "://",
            !typed.hasColon || !typed.schemePrefix.isEmpty || hasPort
        else { return nil }
        let hidesWww = authority.lowercased().hasPrefix("www.") && !typed.authority.hasPrefix("www.")
        let shown = hidesWww ? String(authority.dropFirst(4)) : authority
        let folded = shown.lowercased()
        guard folded.hasPrefix(typed.authority) else { return nil }
        var completedPath = ""
        if let typedPath = typed.path {
            guard typed.authority == folded, path.hasPrefix(typedPath) else { return nil }
            let remainder = path.dropFirst(typedPath.count)
            if let slash = remainder.firstIndex(of: "/") {
                completedPath = String(path[...slash])
            } else {
                completedPath = path + suffix
            }
        }
        let text = typed.schemePrefix + shown + completedPath
        guard text.utf16.count >= typed.text.utf16.count else { return nil }
        return PaletteAddressMatch(
            candidate: self, text: text,
            opens: "\(scheme)://\(authority)\(completedPath.isEmpty ? "/" : completedPath)",
            quality: typed.path != nil ? 3 : typed.authority == folded ? 2 : 1)
    }
}

struct PaletteAddressMatch: Sendable {
    let candidate: PaletteAddressCandidate
    let text: String
    let opens: String
    let quality: Int

    func outranks(_ other: Self, now: Date) -> Bool {
        if quality != other.quality { return quality > other.quality }
        if candidate.source != other.candidate.source { return candidate.source > other.candidate.source }
        func use(_ item: PaletteAddressCandidate) -> Double {
            Double(item.visits) * pow(2, -now.timeIntervalSince(item.date) / (86_400 * 30))
        }
        let own = use(candidate)
        let theirs = use(other.candidate)
        if abs(own - theirs) > 0.001 { return own > theirs }
        if candidate.date != other.candidate.date { return candidate.date > other.candidate.date }
        if text.utf16.count != other.text.utf16.count { return text.utf16.count < other.text.utf16.count }
        if text != other.text { return text.utf16.lexicographicallyPrecedes(other.text.utf16) }
        return candidate.url.utf16.lexicographicallyPrecedes(other.candidate.url.utf16)
    }
}

extension NativePalette {
    func completion(_ question: PaletteSuggestions) -> PaletteAddressMatch? {
        guard let space, question.allowsCompletion, let typed = PaletteTypedAddress(question.text) else { return nil }
        var best: PaletteAddressMatch?
        for candidate in completionCandidates(space) {
            guard let match = candidate.completing(typed) else { continue }
            if match.text.lowercased() == typed.text.lowercased() { return nil }
            if best == nil || match.outranks(best!, now: now) { best = match }
        }
        return best.flatMap { $0.text.utf16.count > typed.text.utf16.count ? $0 : nil }
    }

    private func completionCandidates(_ space: PaletteSpaceSnapshot) -> [PaletteAddressCandidate] {
        var candidates: [PaletteAddressCandidate] = []
        for tab in space.tabs where tab.surface != .startPage {
            if let url = tab.url,
                let item = PaletteAddressCandidate(
                    url, source: tab.placement.isDurable ? 2 : 3, date: tab.lastActivatedAt)
            {
                candidates.append(item)
            }
            if let saved = tab.placement.isDurable ? tab.savedURL ?? tab.url : nil,
                let item = PaletteAddressCandidate(saved, source: 2, date: tab.lastActivatedAt)
            {
                candidates.append(item)
            }
        }
        candidates += space.history.compactMap {
            PaletteAddressCandidate($0.url, source: 1, date: $0.lastVisitedAt, visits: $0.visitCount)
        }
        return candidates
    }

    func intents(_ query: PaletteQuery) -> [PaletteRow] {
        guard !query.isEmpty, let url = resolution?.url, let parsed = URL(string: url) else { return [] }
        if let searched = resolution?.searchQuery { return [searching(searched, url)] }
        let scheme = URL(string: query.text)?.scheme?.lowercased()
        let typedScheme = scheme == "http" || scheme == "https" ? scheme : nil
        let address = known(url, scheme: typedScheme) ?? url
        let host = parsed.host().flatMap { $0.isEmpty ? nil : BrowserWebAddress.withoutWww($0) } ?? url
        return [
            .make(.openAddress, "Open \(host)", address, address: address), searching(query.text, search(query.text)),
        ]
    }

    private func known(_ url: String, scheme: String?) -> String? {
        guard let space, let place = BrowserWebAddress.place(url) else { return nil }
        func same(_ known: String) -> Bool {
            BrowserWebAddress.place(known) == place && (scheme == nil || URL(string: known)?.scheme == scheme)
        }
        for tab in space.tabs {
            if let known = (tab.placement.isDurable ? tab.savedURL : nil) ?? tab.url, same(known) { return known }
        }
        return space.history.prefix(1_500).first { same($0.url) }?.url
    }

    func search(_ text: String) -> String { render(provider.searchTemplate, text) }
    private func render(_ template: String, _ text: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return template.replacingOccurrences(
            of: "%s", with: text.addingPercentEncoding(withAllowedCharacters: unreserved)!)
    }
    func searching(_ text: String, _ address: String) -> PaletteRow {
        .make(.search, "Search \(provider.title)", text, address: address, provider: provider)
    }
    func suggestionAddress(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 256, !isPrivate, space != nil, suggests else { return nil }
        let template: String
        switch provider {
        case .google: template = "https://www.google.com/complete/search?client=chrome&q=%s"
        case .duckDuckGo: template = "https://duckduckgo.com/ac/?q=%s&type=list"
        case .bing: template = "https://www.bing.com/osjson.aspx?query=%s"
        case .brave: template = "https://search.brave.com/api/suggest?q=%s"
        default: return nil
        }
        return render(template, text)
    }
    func suggestions(_ text: String, remote: [String], shown: [PaletteRow]) -> [PaletteRow] {
        guard suggests, !isPrivate else { return [] }
        func collapsed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func folded(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        }
        var claimed = Set(([text] + shown.map(\.title)).map { folded(collapsed($0)) })
        var rows: [PaletteRow] = []
        for fetched in remote {
            if rows.count >= PaletteSection.searchSuggestions.limit { break }
            let suggestion = collapsed(fetched)
            guard !suggestion.isEmpty, suggestion.utf16.count <= 256, claimed.insert(folded(suggestion)).inserted else {
                continue
            }
            rows.append(
                .make(
                    .searchSuggestion, suggestion, "Search \(provider.title)", address: search(suggestion),
                    provider: provider))
        }
        return rows
    }
}
