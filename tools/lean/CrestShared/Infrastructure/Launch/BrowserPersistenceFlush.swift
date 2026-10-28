import Foundation
import OSLog

/// What the app waits for before its process may stop, at quit on the Mac and
/// when a scene leaves the foreground on iOS: every edit the core accepted on
/// disk and staged for sync, and each resident page's state written.
///
/// The wait is bounded, so a save that never finishes cannot hold up a quit
/// the person asked for or outlast the time iOS grants a background task. The
/// work it waits for runs on the main actor, which stays free while it waits:
/// the core's `Saved` arrives through its wake, a main-queue hop and a drain.
struct BrowserPersistenceFlush: Sendable {
    // MARK: - Static Variables

    /// Long enough for a large session's save and stage, short enough that a
    /// stuck save never keeps the app from quitting.
    static let defaultLimit: Duration = .seconds(3)

    // MARK: - Variables

    let limit: Duration

    // MARK: - Initializers

    init(limit: Duration = defaultLimit) {
        self.limit = limit
    }

    // MARK: - Actions - Waiting

    /// Runs `flush` and returns once it finishes or `limit` passes, whichever
    /// comes first. Answers whether it finished; a flush the limit cut short
    /// keeps running for as long as the process does.
    @discardableResult
    func run(_ flush: @escaping @MainActor @Sendable () async -> Void) async -> Bool {
        let (answers, answer) = AsyncStream.makeStream(of: Bool.self)
        let deadline = Task { [limit] in
            do { try await Task.sleep(for: limit) } catch { return }
            answer.yield(false)
        }
        Task { @MainActor in
            await flush()
            answer.yield(true)
        }
        var first = answers.makeAsyncIterator()
        let finished = await first.next() ?? false
        answer.finish()
        deadline.cancel()
        if !finished {
            Logger(subsystem: "com.pauldavis.crest", category: "SessionStorage")
                .error("Pending saves and sync stages were still running after \(limit, privacy: .public)")
        }
        return finished
    }
}
