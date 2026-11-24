import Darwin
import Foundation

struct BrowserCLIResponse: Codable, Sendable {
    struct Space: Codable, Sendable {
        let id: UUID
        let name: String
        let selected: Bool
    }

    struct Tab: Codable, Sendable {
        let id: UUID
        let spaceID: UUID
        let title: String
        let url: URL?
        let placement: BrowserTab.Placement
        let selected: Bool
    }

    var spaces: [Space]?
    var tabs: [Tab]?
    var message: String?
    var error: String?
}

struct BrowserCLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum BrowserCLI {
    static let usage = """
        Usage:
          browser spaces list
          browser spaces create NAME [NAME ...]
          browser spaces select SPACE
          browser spaces rename SPACE NAME
          browser tabs list [--space SPACE]
          browser tabs open URL [--space SPACE]
          browser tabs select TAB_ID
          browser tabs close TAB_ID

        SPACE is a regular Space's name or ID. Commands use the running Browser app.
        """

    static func run(_ arguments: [String]) {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(usage)
            return
        }
        do {
            let request = try JSONEncoder().encode(arguments)
            guard request.count <= BrowserCLISocket.requestLimit else { throw POSIXError(.EMSGSIZE) }
            let path = try BrowserCLISocket.path(in: BrowserPersistence.dataDirectory())
            let descriptor = try BrowserCLISocket.make()
            defer { close(descriptor) }
            do {
                try BrowserCLISocket.withAddress(path) { connect(descriptor, $0, $1) }
            } catch let error as POSIXError where error.code == .ENOENT || error.code == .ECONNREFUSED {
                throw BrowserCLIError("Open an up-to-date Browser and try again.")
            }
            try BrowserCLISocket.requireSameUser(descriptor)
            try BrowserCLISocket.write(request, to: descriptor)
            try BrowserCLISocket.check(shutdown(descriptor, SHUT_WR))
            let data = try BrowserCLISocket.read(descriptor, limit: BrowserCLISocket.responseLimit)
            let response = try JSONDecoder().decode(BrowserCLIResponse.self, from: data)
            if let error = response.error { throw BrowserCLIError(error) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try FileHandle.standardOutput.write(contentsOf: encoder.encode(response))
            print()
        } catch {
            let message = "browser: \(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            exit(1)
        }
    }
}
