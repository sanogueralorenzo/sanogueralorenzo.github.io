import Foundation

enum BrowserReaderModeSnapshotDecoder {
    static func decode(_ value: Any?) throws -> BrowserReaderModeSnapshot {
        guard let value = value as? [String: Any] else {
            throw BrowserReaderModeError.presentationFailed
        }

        return BrowserReaderModeSnapshot(
            isActive: value["isActive"] as? Bool == true,
            title: value["title"] as? String ?? "",
            text: value["text"] as? String ?? "",
            unsafeElementCount: (value["unsafeElementCount"] as? NSNumber)?.intValue ?? 0
        )
    }
}
