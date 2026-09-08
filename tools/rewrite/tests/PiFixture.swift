import Foundation

@MainActor
final class PiFixture {
    let directory: URL
    let executable: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rewrite-core-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        executable = directory.appendingPathComponent("pi.py")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "tests/pi.py"), to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try mode("normal")
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func mode(_ name: String) throws { try name.write(to: directory.appendingPathComponent("mode"), atomically: true, encoding: .utf8) }
    var events: [[String: Any]] {
        let data = (try? Data(contentsOf: directory.appendingPathComponent("events.jsonl"))) ?? Data()
        return data.split(separator: 10).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }
    func count(_ event: String) -> Int { events.filter { $0["event"] as? String == event }.count }
    func cleaned() throws {
        for event in events where event["event"] as? String == "started" {
            try expect(!FileManager.default.fileExists(atPath: event["directory"] as! String), "Temporary credentials survived shutdown")
        }
    }
}
