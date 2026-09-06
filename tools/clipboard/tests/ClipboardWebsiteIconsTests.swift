import AppKit

private final class IconProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var data: Data
        var headers: [String: String] = [:]
        var error: URLError?
    }
    private static let lock = NSLock()
    private static var replies: [String: Reply] = [:]
    private static var requests: [String] = []

    static func reset(_ replies: [String: Reply]) {
        lock.withLock { self.replies = replies; requests = [] }
    }
    static var requested: [String] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let reply = Self.lock.withLock {
            Self.requests.append(url.absoluteString)
            return Self.replies[url.absoluteString] ?? Reply(status: 404, data: Data())
        }
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
enum ClipboardWebsiteIconsTests {
    static func run() async throws {
        let site = URL(string: "https://example.test/")!
        let link = URL(string: "https://name:password@EXAMPLE.test:443/private/pull/8?token=secret#section")!
        precondition(ClipboardWebsiteIcons.origin(for: link) == site)
        precondition(ClipboardWebsiteIcons.origin(for: URL(string: "http://example.test:8080/a")!)?.absoluteString == "http://example.test:8080/")
        precondition(ClipboardWebsiteIcons.origin(for: URL(string: "file:///tmp/icon.png")!) == nil)
        let candidates = ClipboardWebsiteIcons.iconURLs(in: """
        <link href="/style.css" rel="stylesheet">
        <LINK HREF='/brand.png?v=1&amp;size=32' REL='shortcut ICON'>
        <link rel=apple-touch-icon href=//cdn.example.test/touch.png>
        <link href='/brand.png?v=1&amp;size=32' rel=icon>
        <link rel=icon href=data:image/png;base64,ignored>
        <link rel=icon href='https://user:password@example.test/private.png'>
        <link rel=icon type='image/svg+xml' href=/vector>
        <link rel=icon href=/vector.svg>
        """, base: site)
        precondition(candidates.map(\.absoluteString) == ["https://example.test/brand.png?v=1&size=32", "https://cdn.example.test/touch.png"])
        print("PASS: website icon requests strip private URL components and resolve supported icon declarations")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 88, pixelsHigh: 44,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let thumbnail = ClipboardWebsiteIcons.thumbnail(png)!
        precondition(thumbnail.width == 52 && thumbnail.height == 26)
        precondition(ClipboardWebsiteIcons.thumbnail(Data("not an image".utf8)) == nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IconProtocol.self]
        let session = URLSession(configuration: configuration)
        let icons = ClipboardWebsiteIcons(session: session)
        defer { icons.clear(); session.invalidateAndCancel() }
        var completed: [URL] = []
        icons.onChange = { completed.append($0) }
        func load(_ url: URL) async throws {
            let count = completed.count
            precondition(icons.image(for: url) == nil)
            let deadline = Date().addingTimeInterval(2)
            while completed.count == count && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
            precondition(completed.count == count + 1, "Icon lookup did not finish")
        }

        IconProtocol.reset(["https://example.test/favicon.ico": .init(data: png)])
        precondition(icons.image(for: link) == nil)
        try await load(URL(string: "https://example.test/another")!)
        precondition(completed == [site])
        precondition(icons.image(for: link) != nil && icons.image(for: site) != nil)
        precondition(IconProtocol.requested == ["https://example.test/favicon.ico"])
        print("PASS: concurrent links share one fetch and reuse the cached website icon")

        icons.clear()
        IconProtocol.reset([
            site.absoluteString: .init(data: Data("<link rel='icon' href='//cdn.example.test/custom.png'>".utf8)),
            "https://cdn.example.test/custom.png": .init(data: png)
        ])
        try await load(link)
        precondition(icons.image(for: link) != nil)
        precondition(IconProtocol.requested == ["https://example.test/favicon.ico", site.absoluteString, "https://cdn.example.test/custom.png"])
        print("PASS: missing favicon falls back to the website's declared icon")

        for reply in [IconProtocol.Reply(status: 404, data: png), .init(data: Data("invalid".utf8)),
                      .init(data: Data(), error: URLError(.notConnectedToInternet)),
                      .init(data: png, headers: ["Content-Length": "1048577"]),
                      .init(data: Data(repeating: 0, count: 1_048_577))] {
            icons.clear()
            IconProtocol.reset(["https://example.test/favicon.ico": reply])
            try await load(site)
            let count = completed.count
            precondition(icons.image(for: site) == nil)
            try await Task.sleep(for: .milliseconds(20))
            precondition(completed.count == count)
            precondition(IconProtocol.requested == ["https://example.test/favicon.ico", site.absoluteString])
        }
        print("PASS: missing, offline, malformed, and oversized icons leave the fallback in place and cache the miss")

        icons.clear()
        IconProtocol.reset(["https://example.test/favicon.ico": .init(data: png)])
        _ = icons.image(for: site)
        icons.clear()
        try await load(site)
        precondition(icons.image(for: site) != nil)
        print("PASS: clearing the icon cache cancels pending work and allows a fresh lookup")
    }
}
