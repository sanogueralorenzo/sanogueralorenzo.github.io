import Foundation

enum PageAddress {
    static func held(_ spelling: String) -> String? {
        let value = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            SchemeHandling.disposition(scheme: scheme, isAppInitiated: true) == .engine, scheme != "chrome-extension",
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return nil }
        if ["http", "https"].contains(scheme), url.host?.isEmpty != false { return nil }
        return value
    }

    static func samePage(_ first: String, _ second: String) -> Bool {
        Data(key(first).utf8) == Data(key(second).utf8)
    }
    private static func key(_ spelling: String) -> String {
        guard let url = URL(string: spelling.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false,
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return spelling }
        return String(spelling.prefix { $0 != "#" })
    }
}
