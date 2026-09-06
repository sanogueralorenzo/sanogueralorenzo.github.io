import AppKit
import ImageIO

@MainActor
final class ClipboardWebsiteIcons {
    private final class Entry {
        let image: NSImage?
        let expires: Date
        init(image: NSImage?, now: Date) {
            self.image = image
            expires = now.addingTimeInterval(image == nil ? 300 : 86400)
        }
    }

    var onChange: ((URL) -> Void)?
    private let cache = NSCache<NSURL, Entry>()
    private var pending: [URL: Task<Void, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = ClipboardWebsiteIcons.makeSession()) {
        self.session = session
        cache.countLimit = 200
    }

    func image(for url: URL) -> NSImage? {
        guard let origin = Self.origin(for: url) else { return nil }
        if let entry = cache.object(forKey: origin as NSURL), entry.expires > Date() { return entry.image }
        if pending[origin] == nil {
            pending[origin] = Task { [weak self, session] in
                let bitmap = await Self.fetch(origin: origin, session: session)
                guard !Task.isCancelled, let self else { return }
                let image = bitmap.map { NSImage(cgImage: $0, size: .zero) }
                cache.setObject(Entry(image: image, now: Date()), forKey: origin as NSURL)
                pending[origin] = nil
                onChange?(origin)
            }
        }
        return nil
    }

    func clear() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        cache.removeAllObjects()
    }

    nonisolated static func origin(for url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme; parts.host = host.lowercased()
        parts.user = nil; parts.password = nil; parts.path = "/"; parts.query = nil; parts.fragment = nil
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        return parts.url
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    nonisolated private static func fetch(origin: URL, session: URLSession) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let favicon = origin.appendingPathComponent("favicon.ico")
        if let result = try? await download(favicon, session: session, limit: 1_048_576),
           let image = thumbnail(result.data) { return image }
        guard !Task.isCancelled,
              let page = try? await download(origin, session: session, limit: 262_144, allowPrefix: true) else { return nil }
        for url in iconURLs(in: String(decoding: page.data, as: UTF8.self), base: page.url).filter({ $0 != favicon }).prefix(3) {
            guard !Task.isCancelled else { return nil }
            if let result = try? await download(url, session: session, limit: 1_048_576),
               let image = thumbnail(result.data) { return image }
        }
        return nil
    }

    nonisolated private static func download(_ url: URL, session: URLSession, limit: Int, allowPrefix: Bool = false) async throws -> (data: Data, url: URL) {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              allowPrefix || response.expectedContentLength <= limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count == limit {
                if allowPrefix { break }
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return (data, response.url ?? url)
    }

    nonisolated static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 44,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    nonisolated static func iconURLs(in html: String, base: URL) -> [URL] {
        let links = try! NSRegularExpression(pattern: #"<link\b(?:[^\"'<>]|\"[^\"]*\"|'[^']*')*>"#, options: .caseInsensitive)
        let attributes = try! NSRegularExpression(pattern: #"([a-z][a-z0-9:-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#, options: .caseInsensitive)
        let text = html as NSString
        var urls: [URL] = []
        for link in links.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let tag = text.substring(with: link.range) as NSString
            var values: [String: String] = [:]
            for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let value = (2...4).map { attribute.range(at: $0) }.first { $0.location != NSNotFound }!
                values[tag.substring(with: attribute.range(at: 1)).lowercased()] = tag.substring(with: value)
            }
            let relations = (values["rel"] ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
            guard relations.contains("icon") || relations.contains("apple-touch-icon"),
                  let href = values["href"],
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
                  origin(for: url) != nil, url.user == nil, url.password == nil,
                  url.pathExtension.lowercased() != "svg", values["type"]?.lowercased() != "image/svg+xml",
                  !urls.contains(url) else { continue }
            urls.append(url)
        }
        return urls
    }
}
