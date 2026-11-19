import Foundation

struct BrowserContentPackageDownload: Sendable {
    typealias Progress = @MainActor @Sendable (Double) -> Void

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(
            string: "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/browser/Resources/"
        )!
    ) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func latest() async throws -> BrowserContentPackage.Manifest {
        let data = try await receive("uBlockOriginLite.json", limit: 16_384)
        let manifest = try JSONDecoder().decode(BrowserContentPackage.Manifest.self, from: data)
        guard manifest.isSupported else { throw CocoaError(.fileReadCorruptFile) }
        return manifest
    }

    func fetch(progress: Progress? = nil) async throws -> Data {
        try await receive("uBlockOriginLite.zip", limit: BrowserContentPackages.maximumArchiveSize, progress: progress)
    }

    private func receive(_ name: String, limit: Int, progress: Progress? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent(name)
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url == url
        else { throw URLError(.badServerResponse) }
        let expected = response.expectedContentLength
        guard expected <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
            if let progress, expected > 0, data.count.isMultiple(of: 131_072) {
                await progress(min(1, Double(data.count) / Double(expected)))
            }
        }
        return data
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
