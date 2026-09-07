import Foundation

struct Meeting: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var duration: TimeInterval = 0
    var title = "Untitled meeting"
    var body = ""
    var state = "recording"
    var error: String?
    var warning: String?
    var processor: String?
    var metadata: String { date.formatted(date: .abbreviated, time: .shortened) + " · " + Self.elapsed(duration) }
    static func elapsed(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
    var copied: String { "\(title)\n\(metadata)\n\n\(body)" }
}
struct ProcessorSettings: Codable {
    var provider = "local"
    var model = "qwen3:8b"
    var configured = false
}
struct NoteResult: Decodable { let title: String; let body: String }

final class MeetingStore {
    let root: URL
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func save(_ meeting: Meeting) throws {
        let folder = folder(meeting.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(meeting).write(to: folder.appendingPathComponent("meeting.json"), options: .atomic)
        if !meeting.body.isEmpty { try meeting.copied.write(to: folder.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8) }
    }
    func load() throws -> [Meeting] {
        var meetings: [Meeting] = []
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where UUID(uuidString: folder.lastPathComponent) != nil {
            do {
                var meeting = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: folder.appendingPathComponent("meeting.json")))
                guard meeting.id.uuidString == folder.lastPathComponent else { throw CocoaError(.fileReadCorruptFile) }
                if ["recording", "processing"].contains(meeting.state) {
                    meeting.state = "failed"
                    meeting.error = "Minutes closed before finishing. Saved audio and transcript are available; Retry resumes processing."
                    try save(meeting)
                }
                meetings.append(meeting)
            } catch {
                // Never silently drop a damaged meeting or delete its source audio.
                let original = folder.appendingPathComponent("meeting.json")
                let backup = folder.appendingPathComponent("meeting.recovered-original.json")
                if FileManager.default.fileExists(atPath: original.path), !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: original, to: backup)
                }
                var recovered = Meeting(id: UUID(uuidString: folder.lastPathComponent)!, title: "Recovered meeting", state: "failed")
                recovered.error = "Meeting metadata could not be read. Original files are preserved. Retry to rebuild the note."
                meetings.append(recovered)
            }
        }
        return meetings.sorted { $0.date > $1.date }
    }
    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: folder(id)) }
}
