import Darwin
import Foundation
import UniformTypeIdentifiers

struct BrowserDownloadFile {
    static func safeFilename(_ suggested: String) -> String {
        let last =
            suggested.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)
            ?? "download"
        let stripped = String(
            last.precomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
                let n = scalar.value
                return n >= 32 && !(127...159).contains(n) && !(0x200B...0x200F).contains(n)
                    && !(0x202A...0x202E).contains(n) && !(0x2066...0x2069).contains(n) && n != 0x061C && n != 0xFEFF
            }
        ).replacingOccurrences(of: ":", with: "_").trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var name = stripped.isEmpty ? "download" : stripped
        let suffix = (name as NSString).pathExtension
        let ext = suffix.utf8.count <= 32 && !suffix.isEmpty ? "." + suffix : ""
        if name.utf8.count > 240 {
            var stem = ""
            for character in name.dropLast(ext.count) {
                if (stem + String(character)).utf8.count > 240 - ext.utf8.count { break }
                stem.append(character)
            }
            name = stem + ext
        }
        return name
    }

    static func replacementIdentity(at url: URL) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return "\(info.st_dev):\(info.st_ino):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
    }

    static func publish(_ temporary: URL, to destination: URL, replacing identity: String?) throws -> URL {
        if let identity, replacementIdentity(at: destination) == identity {
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return destination
        }
        let directory = destination.deletingLastPathComponent()
        let ext = destination.pathExtension.isEmpty ? "" : "." + destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        var target = destination
        var number = 1
        while renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let suffix = " (\(number))" + ext
            var prefix = stem[...]
            while !prefix.isEmpty && prefix.utf8.count + suffix.utf8.count > 255 { prefix.removeLast() }
            guard prefix.utf8.count + suffix.utf8.count <= 255 else { throw POSIXError(.ENAMETOOLONG) }
            target = directory.appendingPathComponent(String(prefix) + suffix)
            number += 1
        }
        return target
    }

    static func risks(suggested: String, sanitized: String, mime: String?, initiated: Bool) -> [String] {
        let suffix = (sanitized as NSString).pathExtension.lowercased()
        let dangerous: Set<String> = [
            "app", "application", "bat", "bin", "cmd", "com", "command", "csh", "dmg", "exe", "jar", "ksh",
            "mobileconfig", "mpkg", "msi", "pkg", "ps1", "reg", "run", "scpt", "scr", "sh", "tool", "vbs", "workflow",
            "zsh",
        ]
        let extensionType = UTType(filenameExtension: suffix)
        let mimeType = mime.flatMap { UTType(mimeType: $0) }
        func executable(_ type: UTType?) -> Bool {
            guard let type else { return false }
            return type.conforms(to: .executable) || type.conforms(to: .application) || type.conforms(to: .script)
                || type.conforms(to: .diskImage)
        }
        let runs = dangerous.contains(suffix) || executable(extensionType) || executable(mimeType)
        let deceptive = suggested.unicodeScalars.contains {
            (0x200B...0x200F).contains($0.value) || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value) || $0.value == 0x061C || $0.value == 0xFEFF
        }
        var reasons: [String] = []
        if runs && !initiated { reasons.append("This file can install or run software.") }
        if deceptive { reasons.append("The original filename contains invisible or direction-changing characters.") }
        if runs, let a = extensionType, let b = mimeType, !a.conforms(to: b), !b.conforms(to: a) {
            reasons.append("The server's file type does not match the filename.")
        }
        return reasons
    }
}
