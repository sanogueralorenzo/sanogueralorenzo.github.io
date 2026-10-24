import Darwin
import Foundation

// crest-browser, the helper agents run to use Crest:
//
//   crest-browser mcp
//
// speaks the Model Context Protocol over its standard streams and reaches the
// Crest app it ships inside, which must be running with agents turned on.

let usage = "usage: crest-browser mcp\n"
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "mcp" else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}

/// The socket of the Crest this helper ships inside, at
/// Crest.app/Contents/Helpers/crest-browser, unless a review run names one.
@MainActor func socketPath() -> String? {
    if let index = arguments.firstIndex(of: "--socket"), arguments.indices.contains(index + 1) {
        return arguments[index + 1]
    }
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app", let identifier = Bundle(url: app)?.bundleIdentifier else { return nil }
    return AgentSocketLocation.path(forApp: identifier)
}

signal(SIGPIPE, SIG_IGN)
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
let streams = AgentLineChannel(input: STDIN_FILENO, output: STDOUT_FILENO)
let endpoint = AgentHelperEndpoint(output: streams, link: AgentAppLink(path: socketPath()), version: version)
for await line in streams.lines() {
    await endpoint.receive(line)
}
exit(0)
