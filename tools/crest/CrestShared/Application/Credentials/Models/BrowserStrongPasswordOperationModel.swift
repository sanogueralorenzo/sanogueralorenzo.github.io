import Observation

@Observable
@MainActor
final class BrowserStrongPasswordOperationModel {

    typealias PasswordGenerator = @MainActor () throws -> String
    typealias PasswordSaver = @MainActor (String) async throws -> Void
    typealias PasswordFiller = @MainActor (String) async throws -> Void

    private(set) var phase = BrowserStrongPasswordOperationPhase.idle

    var isWorking: Bool {
        phase == .working
    }

    func generateSaveAndFill(
        generate: PasswordGenerator,
        save: PasswordSaver,
        fill: PasswordFiller
    ) async {
        guard !isWorking else { return }
        phase = .working

        do {
            let password = try generate()
            do {
                try await save(password)
            } catch {
                phase = Task.isCancelled ? .idle : .failedBeforeSave
                return
            }
            do {
                try await fill(password)
                phase = .idle
            } catch {
                phase = Task.isCancelled ? .idle : .savedButFillFailed
            }
        } catch {
            phase = Task.isCancelled ? .idle : .failedBeforeSave
        }
    }
}

enum BrowserStrongPasswordOperationPhase: Equatable, Sendable {
    case idle
    case working
    case failedBeforeSave
    case savedButFillFailed
}
