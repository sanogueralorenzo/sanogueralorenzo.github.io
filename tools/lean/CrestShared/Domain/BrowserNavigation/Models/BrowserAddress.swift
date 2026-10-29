import Foundation

struct ResolvedAddress: Equatable, Sendable {
    let url: String?
    let searchQuery: String?
}

/// Resolves typed input without touching the file system or a page runtime.
enum BrowserAddress {
    static func resolve(_ input: String, provider: SearchProvider = .google) -> ResolvedAddress {
        let value = trimmed(input)
        guard !value.isEmpty, value.utf16.count <= 4096 else { return ResolvedAddress(url: nil, searchQuery: nil) }
        let lower = value.lowercased()
        if value != "about:blank", !["chrome://", "crest://", "chrome-extension://"].contains(where: lower.hasPrefix) {
            if let url = webURL(value), url.host?.isEmpty == false {
                return ResolvedAddress(url: value, searchQuery: nil)
            }
            if let file = localFile(value) { return ResolvedAddress(url: file, searchQuery: nil) }
            if !value.unicodeScalars.contains(where: { $0.properties.isWhitespace }),
                let url = webURL("http://" + value), let host = url.host?.lowercased()
            {
                let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                let ipv4 = host.split(separator: ".", omittingEmptySubsequences: false)
                let localIPv4 =
                    ipv4.count == 4
                    && ipv4.allSatisfy { part in
                        guard let byte = UInt8(part) else { return false }
                        return String(byte) == part
                    } && value.hasPrefix(host)
                let localIPv6 = host.contains(":")
                if localIPv6 || localIPv4 || host == "localhost"
                    || [".localhost", ".local", ".home.arpa", ".internal"].contains(where: host.hasSuffix)
                {
                    return ResolvedAddress(url: "http://" + value, searchQuery: nil)
                }
                if value.contains(".") { return ResolvedAddress(url: "https://" + value, searchQuery: nil) }
            }
        }
        return ResolvedAddress(url: provider.search(value), searchQuery: value)
    }

    /// The blank document loads directly even though the palette treats its name as a search.
    static func loading(_ input: String, provider: SearchProvider = .google) -> String? {
        let value = trimmed(input)
        if value == "about:blank" || value.hasPrefix("about:blank#") { return value }
        return resolve(input, provider: provider).url
    }

    static func webURL(_ spelling: String) -> URL? {
        guard let url = URL(string: spelling), ["http", "https"].contains(url.scheme?.lowercased()),
            let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host, !host.isEmpty,
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return nil }
        if host.hasPrefix("[") {
            guard host.hasSuffix("]"), ipv6(String(host.dropFirst().dropLast())) else { return nil }
        } else {
            var labels = host.split(separator: ".", omittingEmptySubsequences: false)
            if labels.last?.isEmpty == true { labels.removeLast() }
            guard !labels.isEmpty,
                labels.allSatisfy({ label in
                    !label.isEmpty
                        && label.unicodeScalars.allSatisfy {
                            $0.value > 127 || (48...57).contains($0.value) || (65...90).contains($0.value)
                                || (97...122).contains($0.value) || $0 == "-" || $0 == "_"
                        }
                })
            else { return nil }
        }
        return url
    }

    static func trimmed(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.unicodeScalars.drop(while: { $0.properties.isWhitespace })
                    .reversed().drop(while: { $0.properties.isWhitespace }).reversed()))
    }

    private static func ipv6(_ host: String) -> Bool {
        let address = String(host.prefix { $0 != "%" })
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2, halves.allSatisfy({ !$0.hasPrefix(":") && !$0.hasSuffix(":") }) else { return false }
        let groups = address.split(separator: ":", omittingEmptySubsequences: true)
        var count = 0
        for (index, group) in groups.enumerated() {
            if group.contains(".") {
                let bytes = group.split(separator: ".", omittingEmptySubsequences: false)
                guard index == groups.count - 1, bytes.count == 4,
                    bytes.allSatisfy({ UInt8($0) != nil })
                else { return false }
                count += 2
            } else {
                guard (1...4).contains(group.count), group.allSatisfy(\.isHexDigit) else { return false }
                count += 1
            }
        }
        return halves.count == 2 ? count < 8 : count == 8 && !address.hasPrefix(":") && !address.hasSuffix(":")
    }

    private static func localFile(_ value: String) -> String? {
        var candidate = value
        if value.hasPrefix("~") {
            guard value == "~" || value.hasPrefix("~/") else { return nil }
            candidate = FileManager.default.homeDirectoryForCurrentUser.path + value.dropFirst()
        }
        if candidate.hasPrefix("/"), !candidate.hasPrefix("//") {
            var parts = URLComponents()
            parts.scheme = "file"
            parts.host = ""
            parts.path = candidate
            return parts.url?.absoluteString
        }
        guard candidate.lowercased().hasPrefix("file://"),
            var parts = URLComponents(string: candidate), parts.user == nil, parts.password == nil,
            !parts.path.isEmpty, parts.host?.isEmpty != false || parts.host?.lowercased() == "localhost"
        else { return nil }
        parts.scheme = "file"
        parts.host = ""
        return parts.url?.absoluteString
    }
}

extension SearchProvider {
    func search(_ text: String) -> String { render(searchTemplate, text) }
    func suggest(_ text: String) -> String? {
        let template: String
        switch self {
        case .google: template = "https://www.google.com/complete/search?client=chrome&q=%s"
        case .duckDuckGo: template = "https://duckduckgo.com/ac/?q=%s&type=list"
        case .bing: template = "https://www.bing.com/osjson.aspx?query=%s"
        case .brave: template = "https://search.brave.com/api/suggest?q=%s"
        default: return nil
        }
        return render(template, text)
    }
    private func render(_ template: String, _ text: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return template.replacingOccurrences(
            of: "%s", with: text.addingPercentEncoding(withAllowedCharacters: unreserved)!)
    }
}
