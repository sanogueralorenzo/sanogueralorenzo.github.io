import Synchronization

/// Asks iCloud whether an account is signed in, waiting on the answer no
/// longer than `deadline`. iCloud can leave the question unanswered for
/// minutes, as a simulator's `cloudd` does; a check that outlasts the deadline
/// fails with `BrowserCloudSyncError.accountCheckUnanswered`, so the start it
/// belongs to ends and the core retries it as it retries any launch that could
/// not reach iCloud. The question itself is not withdrawn: its late answer is
/// dropped, and the retry asks again.
struct BrowserCloudAccountCheck: Sendable {
    // MARK: - Types

    /// The check's one answer: iCloud's, or the deadline's, whichever comes
    /// first.
    private final class FirstAnswer: Sendable {
        private let continuation: Mutex<CheckedContinuation<CloudAccountState, any Error>?>

        init(_ continuation: CheckedContinuation<CloudAccountState, any Error>) {
            self.continuation = Mutex(continuation)
        }

        func resume(with result: Result<CloudAccountState, any Error>) {
            continuation.withLock { $0.take() }?.resume(with: result)
        }
    }

    // MARK: - Variables

    let remote: any BrowserCloudSyncRemoteService
    let deadline: Duration

    // MARK: - Actions - Checking

    /// The signed-in account's state, as iCloud answers it before the
    /// deadline.
    func state() async throws -> CloudAccountState {
        let remote = remote
        let deadline = deadline
        return try await withCheckedThrowingContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let expiry = Task {
                try await Task.sleep(for: deadline)
                answer.resume(with: .failure(BrowserCloudSyncError.accountCheckUnanswered))
            }
            Task {
                do {
                    answer.resume(with: .success(try await remote.accountState()))
                } catch {
                    answer.resume(with: .failure(error))
                }
                expiry.cancel()
            }
        }
    }
}
