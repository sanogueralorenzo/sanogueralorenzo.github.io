import Foundation

struct NoteResult: Decodable { let title: String; let body: String }

@MainActor
final class ProcessingJob {
    let folder: URL
    private let support: URL
    private let worker: URL
    private var process: Process?
    var progress: String { (try? String(contentsOf: folder.appendingPathComponent("progress.txt"), encoding: .utf8)) ?? "Processing…" }

    init(folder: URL, support: URL, worker: URL = Bundle.main.resourceURL!.appendingPathComponent("worker.py")) {
        self.folder = folder; self.support = support; self.worker = worker
    }
    func start(provider: Provider, completion: @escaping (Result<NoteResult, Error>) -> Void) throws {
        guard process == nil else { throw MinutesError("This meeting is already being processed.") }
        for name in ["result.json", "progress.txt", "error.txt", "processor.json"] {
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        let process = Process()
        process.executableURL = support.appendingPathComponent("runtime/bin/python3")
        process.arguments = [worker.path, folder.path, provider.rawValue, support.appendingPathComponent("moonshine.json").path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path, environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        let log = folder.appendingPathComponent("processing.log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle; process.standardError = handle
        process.terminationHandler = { [weak self] process in
            try? handle.close()
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                completion(Result { try Self.readResult(folder: self.folder, exitCode: process.terminationStatus) })
            }
        }
        do { try process.run(); self.process = process }
        catch { process.terminationHandler = nil; try? handle.close(); throw error }
    }
    static func readResult(folder: URL, exitCode: Int32) throws -> NoteResult {
        struct Output: Decodable { let note: NoteResult?; let error: String? }
        let url = folder.appendingPathComponent("result.json")
        guard let data = try? Data(contentsOf: url), let output = try? JSONDecoder().decode(Output.self, from: data),
              (output.note != nil) != (output.error != nil) else {
            throw MinutesError("Processing ended without a complete result (status \(exitCode)). Retry the saved meeting.")
        }
        if let error = output.error { throw MinutesError(error) }
        guard exitCode == 0, let note = output.note,
              !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinutesError("Processing did not return a complete note. Retry the saved meeting.")
        }
        return note
    }
    func cancel() { if let process, process.isRunning { process.terminate() } }
    deinit { if let process, process.isRunning { process.terminate() } }
}
