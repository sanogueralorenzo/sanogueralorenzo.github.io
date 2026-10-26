import Foundation
import Network

/// Real loopback HTTP requests expose cookie/header normalization and redirect
/// behavior that URLProtocol stubs and source assertions cannot establish.
final class BrowserPrivacyHTTPServer: @unchecked Sendable {
    struct Request: CustomStringConvertible {
        let path: String
        let query: String?
        let headers: [String: String]
        var host: String { headers["host", default: ""] }
        var description: String { "\(host)\(path) \(headers)" }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "CrestTests.FaviconPrivacy.HTTP")
    private let lock = NSLock()
    private var captured: [Request] = []
    private let tls: Bool
    var overrideResponse: ((Request) -> (status: String, headers: String, body: Data))?
    var port: UInt16 { listener.port!.rawValue }
    var requests: [Request] { lock.withLock { captured } }

    init(tls: Bool = false) throws {
        self.tls = tls
        let parameters: NWParameters
        if tls {
            let data = try Self.makeTemporaryTLSIdentity()
            var imported: CFArray?
            let status = SecPKCS12Import(
                data as CFData,
                [
                    kSecImportExportPassphrase: "favicon-fixture",
                    kSecImportToMemoryOnly: true,
                ] as CFDictionary, &imported)
            guard status == errSecSuccess,
                let item = (imported as? [[String: Any]])?.first,
                let identity = item[kSecImportItemIdentity as String]
            else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(
                options.securityProtocolOptions, sec_identity_create(identity as! SecIdentity)!)
            parameters = NWParameters(tls: options)
        } else {
            parameters = .tcp
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Generate an identity for this loopback listener only. No signing material
    /// is committed, trusted system-wide, or imported into a persistent keychain.
    private static func makeTemporaryTLSIdentity() throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crest-favicon-tls-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for arguments in [
            [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem", "-out", "cert.pem", "-days", "1",
                "-subj", "/CN=parent.localhost",
            ],
            [
                "pkcs12", "-export", "-inkey", "key.pem", "-in", "cert.pem", "-out", "identity.p12", "-passout",
                "pass:favicon-fixture",
            ],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "FaviconPrivacyTLSFixture", code: Int(process.terminationStatus))
            }
        }
        return try Data(contentsOf: directory.appending(path: "identity.p12"))
    }

    func url(host: String, path: String) -> URL {
        URL(string: "\(tls ? "https" : "http")://\(host):\(port)\(path)")!
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: queue)
                receive(connection, data: Data())
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            let data = data + (chunk ?? Data())
            if let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") {
                respond(connection, text: text)
            } else if !complete, error == nil, data.count < 65_536 {
                receive(connection, data: data)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(_ connection: NWConnection, text: String) {
        let lines = text.components(separatedBy: "\r\n")
        let target = String(lines[0].split(separator: " ")[1])
        let path = URLComponents(string: target)?.path ?? target
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(
                in: .whitespaces)
        }
        let request = Request(path: path, query: URLComponents(string: target)?.query, headers: headers)
        lock.withLock { captured.append(request) }
        if path.hasPrefix("/oversized-") {
            let head =
                "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8),
                completion: .contentProcessed { [weak self] error in
                    if error == nil { self?.stream(connection, remainingChunks: 500) }
                })
            return
        }
        let response = overrideResponse?(request) ?? response(for: request)
        // Suppress WebKit's independent manifest loader so the wire transcript
        // measures Crest's capture. Fetch uses connect-src, not manifest-src.
        let policy = response.headers.contains("text/html") ? "Content-Security-Policy: manifest-src 'none'\r\n" : ""
        let head =
            "HTTP/1.1 \(response.status)\r\n\(response.headers)\(policy)Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func stream(_ connection: NWConnection, remainingChunks: Int) {
        guard remainingChunks > 0 else {
            connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunk = Data("10000\r\n".utf8) + Data(repeating: 65, count: 65_536) + Data("\r\n".utf8)
        connection.send(
            content: chunk,
            completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    connection.cancel()
                    return
                }
                queue.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.stream(connection, remainingChunks: remainingChunks - 1)
                }
            })
    }

    private func response(for request: Request) -> (status: String, headers: String, body: Data) {
        switch request.path {
        case "/same-site-cookies":
            return (
                "200 OK",
                "Content-Type: text/html\r\nSet-Cookie: strictOther=strict; Path=/; SameSite=Strict\r\nSet-Cookie: laxOther=lax; Path=/; SameSite=Lax\r\n",
                Data("<html>Other site</html>".utf8)
            )
        case "/downgrade-icon":
            let port = request.query!.replacingOccurrences(of: "port=", with: "")
            return (
                "302 Found",
                "Location: http://child.parent.localhost:\(port)/cors-icon\r\nReferrer-Policy: unsafe-url\r\n", Data()
            )
        case "/credential-icon-redirect":
            return (
                "302 Found",
                "Location: http://redirect-user:redirect-password@child.parent.localhost:\(port)/policy-icon#redirect-fragment\r\nSet-Cookie: redirectCookie=unnecessary; Domain=parent.localhost; Path=/\r\n",
                Data()
            )
        case "/auth-icon":
            return ("401 Unauthorized", "WWW-Authenticate: Basic realm=\"Fixture\"\r\n", Data())
        case "/private/page":
            return (
                "200 OK",
                "Content-Type: text/html\r\nReferrer-Policy: no-referrer\r\nSet-Cookie: hostOnly=spaceA; Path=/; HttpOnly; SameSite=Lax\r\nSet-Cookie: domainCookie=domain; Domain=parent.localhost; Path=/\r\nSet-Cookie: privatePath=private; Path=/private\r\nSet-Cookie: secureOnly=secure; Path=/; Secure\r\n",
                Data("<html><head></head><body>Fixture</body></html>".utf8)
            )
        case "/other-space":
            return (
                "200 OK", "Content-Type: text/html\r\nSet-Cookie: spaceB=other; Path=/\r\n",
                Data("<html>Other Space</html>".utf8)
            )
        case "/policy/no-referrer", "/policy/origin":
            let policy = request.path.components(separatedBy: "/").last!
            return (
                "200 OK", "Content-Type: text/html\r\nReferrer-Policy: \(policy)\r\n",
                Data("<html><head><meta name='referrer' content='\(policy)'></head><body>Fixture</body></html>".utf8)
            )
        case "/private/manifest-redirect":
            return ("302 Found", "Location: /private/manifest.json\r\n", Data())
        case "/private/manifest.json":
            guard request.headers["cookie", default: ""].contains("hostOnly=spaceA") else {
                return ("401 Unauthorized", "", Data())
            }
            let manifest = """
                {"icons":[
                  {"src":"http://child.parent.localhost:\(port)/child-icon"},
                  {"src":"/private/cross-site-icon-redirect"},
                  {"src":"/privateer/icon"},
                  {"src":"/private/icon-redirect"}
                ]}
                """
            return ("200 OK", "Content-Type: application/manifest+json\r\n", Data(manifest.utf8))
        case "/private/cross-site-icon-redirect":
            return (
                "302 Found",
                "Location: http://other.localhost:\(port)/same-site-icon\r\nReferrer-Policy: unsafe-url\r\n", Data()
            )
        case "/private/icon-redirect":
            return ("302 Found", "Location: /public/icon\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/public/icon":
            guard request.headers["cookie", default: ""].contains("hostOnly=spaceA") else {
                return ("401 Unauthorized", "", Data())
            }
            return iconResponse()
        case "/policy-icon-redirect":
            return (
                "302 Found",
                "Location: /policy-icon\r\nReferrer-Policy: unsafe-url\r\nSet-Cookie: redirectCookie=unnecessary; Path=/\r\n",
                Data()
            )
        case "/policy-manifest-redirect":
            return ("302 Found", "Location: /policy-manifest.json\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/policy-manifest.json":
            return (
                "200 OK", "Content-Type: application/manifest+json\r\n",
                Data(#"{"icons":[{"src":"policy-manifest-icon-redirect"}]}"#.utf8)
            )
        case "/policy-manifest-icon-redirect":
            return ("302 Found", "Location: /policy-manifest-icon\r\nReferrer-Policy: unsafe-url\r\n", Data())
        case "/cors-icon":
            let icon = iconResponse()
            return (icon.status, icon.headers + "Access-Control-Allow-Origin: *\r\n", icon.body)
        case "/policy-icon":
            return iconResponse()
        default:
            return ("404 Not Found", "", Data())
        }
    }

    private func iconResponse() -> (status: String, headers: String, body: Data) {
        (
            "200 OK", "Content-Type: image/svg+xml\r\n",
            Data(
                #"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="blue"/></svg>"#
                    .utf8)
        )
    }
}
