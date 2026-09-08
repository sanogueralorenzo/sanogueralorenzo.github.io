import Foundation
import AppKit

@main
@MainActor
struct RewriteTests {
    static var passed = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { fatalError("FAIL: " + name) }; passed += 1
    }
    static func rejects(_ name: String, _ block: () throws -> Void) {
        do { try block(); fatalError("FAIL: " + name) } catch { passed += 1 }
    }
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        do {
            if CommandLine.arguments.contains("--live") { try await livePi(); return }
            if CommandLine.arguments.contains("--pi-check") { try await installedPi(); return }
            try await editing()
            try await selection()
            try await piRequests()
            try await piResponses()
            try await piRPC()
            try await processRunner()
            try await piService()
            print("PASS: \(passed) focused checks")
        } catch { print("FAIL: " + error.localizedDescription); exit(1) }
    }
}
