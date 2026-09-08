import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

// The assertion is outside the catch: success can never catch its own failure.
@MainActor
func expectFailure(_ matches: (Error) -> Bool, _ operation: () async throws -> Void) async throws {
    var caught: Error?
    do { try await operation() } catch { caught = error }
    guard let error = caught else { throw TestFailure(description: "Expected an error, but the operation succeeded") }
    try expect(matches(error), "Unexpected error: \(error)")
}

func messageContains(_ fragment: String) -> (Error) -> Bool {
    { error in
        guard case RewriteError.message(let message) = error else { return false }
        return message.contains(fragment)
    }
}

@MainActor
func eventually(_ message: String, _ condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        try expect(ProcessInfo.processInfo.systemUptime < deadline, message)
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@main
@MainActor
struct CoreTests {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        let scenarios: [(String, () async throws -> Void)] = [
            ("Provider defaults and persistence", ValidationTests.providers),
            ("Editing output boundaries", ValidationTests.editing),
            ("Completed output copies exactly; invalid output preserves clipboard", ValidationTests.clipboard),
            ("Completed text only", ValidationTests.responses),
            ("Pi isolation, provider changes and process reuse", PiTests.lifecycle),
            ("Cancellation stops an active rewrite", PiTests.cancellation),
            ("Protocol failures stop Pi and permit recovery", PiTests.failures),
            ("RPC timeout stops the waiting process", PiTests.timeout),
            ("Process IO and exit status", ProcessTests.io),
            ("Process timeout, cancellation and output limit", ProcessTests.failures)
        ]
        for (name, test) in scenarios {
            do { try await test(); print("PASS: \(name)") }
            catch { print("FAIL: \(name): \(error)"); exit(1) }
        }
        print("PASS: \(scenarios.count) core scenarios; no model calls or desktop interaction")
    }
}
