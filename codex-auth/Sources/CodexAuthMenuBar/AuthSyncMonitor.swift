import CodexAuthCore
import Foundation

final class AuthSyncMonitor {
    private struct FileSnapshot: Equatable {
        let modificationTime: TimeInterval
        let size: Int64
        let inode: Int64
    }

    private let homeDirectory: URL
    private let authFilePath: String
    private let onDidSync: @MainActor () -> Void
    private let onError: @MainActor (Error) -> Void
    private let queue = DispatchQueue(label: "CodexAuth.AuthSyncMonitor")
    private var timer: DispatchSourceTimer?
    private var lastSnapshot: FileSnapshot?

    init(homeDirectory: URL,
         onDidSync: @escaping @MainActor () -> Void,
         onError: @escaping @MainActor (Error) -> Void) {
        self.homeDirectory = homeDirectory
        self.authFilePath = AuthPaths(homeDirectory: homeDirectory).codexAuthFile.path
        self.onDidSync = onDidSync
        self.onError = onError
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        lastSnapshot = snapshot()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        let newSnapshot = snapshot()
        guard newSnapshot != lastSnapshot else {
            return
        }
        lastSnapshot = newSnapshot

        do {
            let backgroundManager = ProfileManager(homeDirectory: homeDirectory)
            if try backgroundManager.syncActiveProfileWithCurrentAuth() {
                DispatchQueue.main.async { [onDidSync] in
                    onDidSync()
                }
            }
        } catch {
            if shouldIgnore(error) {
                return
            }
            DispatchQueue.main.async { [onError] in
                onError(error)
            }
        }
    }

    private func snapshot() -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: authFilePath) else {
            return nil
        }

        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? -1
        return FileSnapshot(modificationTime: mtime, size: size, inode: inode)
    }

    private func shouldIgnore(_ error: Error) -> Bool {
        guard let managerError = error as? AuthManagerError else {
            return false
        }
        switch managerError {
        case .invalidAuthFile, .missingCurrentToken:
            return true
        case .ioFailure(let message):
            return message.localizedCaseInsensitiveContains("File not found")
        default:
            return false
        }
    }
}
