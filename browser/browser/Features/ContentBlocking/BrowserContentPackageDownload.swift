import Foundation

struct BrowserContentRelease: Sendable {
    let version: String
    let sha256: String
    let size: Int

    var assetName: String { "uBOLite_\(version).safari.zip" }
}

struct BrowserContentPackageDownload: Sendable {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let digest: String?
        }

        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private static let latestURL = URL(string: "https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/latest")!
    private static let assetsURL = URL(string: "https://github.com/uBlockOrigin/uBOL-home/releases/download/")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: AssetRedirect(), delegateQueue: nil)
    }

    func latest() async throws -> BrowserContentRelease {
        let data = try await receive(Self.latestURL, limit: 512 * 1_024)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        let version = release.tagName
        guard !release.draft, !release.prerelease, BrowserContentPackage.isVersion(version),
            let asset = release.assets.first(where: { $0.name == "uBOLite_\(version).safari.zip" }),
            (1...BrowserContentPackages.maximumArchiveSize).contains(asset.size),
            let digest = asset.digest, digest.hasPrefix("sha256:")
        else { throw CocoaError(.fileReadCorruptFile) }
        let hash = String(digest.dropFirst("sha256:".count))
        guard BrowserContentPackage.isDigest(hash) else { throw CocoaError(.fileReadCorruptFile) }
        return BrowserContentRelease(version: version, sha256: hash, size: asset.size)
    }

    func fetch(_ release: BrowserContentRelease) async throws -> Data {
        let url = Self.assetsURL.appendingPathComponent(release.version).appendingPathComponent(release.assetName)
        return try await receive(url, limit: release.size)
    }

    private func receive(_ url: URL, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let expected = response.expectedContentLength
        guard expected <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private final class AssetRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard response.url?.host == "github.com", let url = request.url,
                url.scheme == "https", url.host == "release-assets.githubusercontent.com",
                url.port == nil, url.user == nil, url.password == nil
            else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}
