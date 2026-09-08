import Foundation

@MainActor
enum ProcessingJobTests {
    static func run(root: URL) async throws {
        let support = root.appendingPathComponent("job-runtime")
        let executable = support.appendingPathComponent("runtime/bin/python3")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = #"""
        #!/bin/sh
        set -eu
        [ "$3" = "openai" ]
        [ "$PYTHONDONTWRITEBYTECODE" = 1 ]
        case "$1" in
          */cancel) exec /bin/sleep 30 ;;
          */failure) printf '%s' '{"error":"Fixture sign-in failure"}' > "$2/result.json"; exit 1 ;;
          *) printf '%s' 'Writing note' > "$2/progress.txt"
             printf '%s' '{"note":{"title":"Fixture note","body":"The draft is approved."}}' > "$2/result.json" ;;
        esac
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        for mode in ["success", "failure", "cancel"] {
            let folder = root.appendingPathComponent("job-" + mode)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let job = ProcessingJob(folder: folder, support: support, worker: root.appendingPathComponent(mode))
            let result: Result<NoteResult, Error> = await withCheckedContinuation { continuation in
                do {
                    try job.start(provider: .openai) { continuation.resume(returning: $0) }
                    if mode == "cancel" { job.cancel() }
                } catch { continuation.resume(returning: .failure(error)) }
            }
            switch result {
            case .success(let note):
                try expect(mode == "success" && note.title == "Fixture note", "Only successful jobs return notes")
                try expect(job.progress == "Writing note", "Job owns progress reading")
            case .failure(let error):
                try expect(mode != "success", "A complete worker result must succeed")
                if mode == "failure" { try expect(error.localizedDescription == "Fixture sign-in failure", "Worker errors reach the app intact") }
            }
            try expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("processor.json").path), "Provider is passed directly")
        }
    }
}
