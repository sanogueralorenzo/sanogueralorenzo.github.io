import Foundation

enum BrowserAddressMatch {
    static func hostName(_ address: URL?) -> String? {
        guard let host = address?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func pageScore(_ query: String, title: String, address: URL?) -> Double? {
        guard !query.isEmpty else { return 0 }
        return hostScore(query, address: address) ??
            [textScore(query, in: title), address.flatMap { textScore(query, in: $0.absoluteString) }]
            .compactMap { $0 }.max()
    }

    static func hostScore(_ query: String, address: URL?) -> Double? {
        guard !query.isEmpty, let host = hostName(address).map(folded) else { return nil }
        if host == query { return 280 }
        if host.hasPrefix(query) { return 260 }
        if host.split(separator: ".").dropLast().contains(where: { $0.hasPrefix(query) }) { return 250 }
        return nil
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func textScore(_ query: String, in text: String, allowsFuzzy: Bool = false) -> Double? {
        guard !query.isEmpty else { return 0 }
        let text = folded(text)
        if text == query { return 200 }
        if text.hasPrefix(query) { return 150 - Double(text.count - query.count) * 0.05 }
        var start = text.startIndex
        while let range = text.range(of: query, range: start..<text.endIndex) {
            let preceding = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            if allowsFuzzy || preceding.map({ !$0.isLetter && !$0.isNumber }) != false {
                return 100 - Double(text.distance(from: text.startIndex, to: range.lowerBound)) * 0.3
            }
            start = text.index(after: range.lowerBound)
        }
        guard allowsFuzzy else { return nil }
        var cursor = text.startIndex
        var gap = 0
        for character in query {
            guard let index = text[cursor...].firstIndex(of: character) else { return nil }
            gap += text.distance(from: cursor, to: index)
            cursor = text.index(after: index)
        }
        return max(0, 45 - Double(gap))
    }
}
