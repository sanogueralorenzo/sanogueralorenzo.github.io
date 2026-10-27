import AppKit
import Foundation
import UniformTypeIdentifiers

struct BrowserImportSource: Identifiable {
    let id: String
    let name: String
    let directory: URL
    static var installed: [BrowserImportSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths: [(String, String, String)] = [
            ("com.apple.Safari", "Safari", "Library/Safari"),
            ("com.google.Chrome", "Chrome", "Library/Application Support/Google/Chrome"),
            ("com.brave.Browser", "Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
            ("com.microsoft.edgemac", "Edge", "Library/Application Support/Microsoft Edge"),
            ("company.thebrowser.Browser", "Arc", "Library/Application Support/Arc"),
            ("company.thebrowser.dia", "Dia", "Library/Application Support/Dia"),
            ("org.mozilla.firefox", "Firefox", "Library/Application Support/Firefox/Profiles"),
            ("app.zen-browser.zen", "Zen", "Library/Application Support/zen/Profiles"),
            ("com.vivaldi.Vivaldi", "Vivaldi", "Library/Application Support/Vivaldi"),
            ("com.operasoftware.Opera", "Opera", "Library/Application Support/com.operasoftware.Opera"),
        ]
        return paths.compactMap { id, name, path in
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return nil }
            return BrowserImportSource(
                id: id, name: name, directory: home.appendingPathComponent(path, isDirectory: true))
        }
    }
}

extension BrowserStore {
    func importBrowserData() { importPresented = true }
    func exportBrowserData() { exportPresented = true }
    func readImportFiles(_ urls: [URL]) async throws -> [BrowserSpace] {
        var result: [BrowserSpace] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let files = try Self.importFiles(in: url)
                var failures: [String] = []
                for file in files {
                    do { result += try BrowserImportReader.read(file) } catch {
                        failures.append(file.lastPathComponent)
                    }
                }
                if result.isEmpty && !failures.isEmpty { throw CocoaError(.fileReadCorruptFile) }
            } else {
                result += try BrowserImportReader.read(url)
            }
            guard result.count + session.spaces.count <= 64 else { throw CocoaError(.fileReadTooLarge) }
        }
        var candidate = BrowserSession()
        candidate.spaces = result
        try candidate.validate()
        return result
    }
    static func importFiles(in directory: URL, depth: Int = 0) throws -> [URL] {
        guard depth < 4 else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles
        )
        let names: Set<String> = [
            "Bookmarks", "AccountBookmarks", "Bookmarks.plist", "LastSession.plist", "Session.plist",
            "StorableSidebar.json", "sessionstore.jsonlz4", "recovery.jsonlz4", "sessionstore.json",
            "zen-sessions.json", "zen-sessions.jsonlz4",
        ]
        var result: [URL] = []
        // Only session/bookmark candidates are read; passwords, cookies, keys, extensions, and history databases stay untouched.
        for url in files {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if depth == 0
                    || ["Sessions", "sessionstore-backups", "User Data", "Default"].contains(url.lastPathComponent)
                    || url.lastPathComponent.hasPrefix("Profile ")
                {
                    result += try importFiles(in: url, depth: depth + 1)
                }
            } else if names.contains(url.lastPathComponent) {
                result.append(url)
            }
        }
        let sessions = files.filter { $0.lastPathComponent.hasPrefix("Session_") }.sorted {
            $0.lastPathComponent > $1.lastPathComponent
        }
        if let latest = sessions.first { result.append(latest) }
        // Prefer the latest Firefox recovery checkpoint over the older shutdown file.
        if result.contains(where: { $0.lastPathComponent == "recovery.jsonlz4" }) {
            result.removeAll { $0.lastPathComponent == "sessionstore.jsonlz4" }
        }
        return result
    }
    func acceptImport(_ spaces: [BrowserSpace]) throws {
        let imported = BrowserImportReader.remapped(spaces)
        var candidate = session
        candidate.spaces += imported
        try candidate.validate()
        session = candidate
        if let first = imported.first { selectSpace(first.id) }
        for space in imported { _ = integration(for: space.id) }
        changed()
    }
    func saveExport(bookmarks: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = bookmarks ? "Lean Bookmarks.html" : "Lean Browser Data.lean"
        panel.allowedContentTypes = bookmarks ? [.html] : [.json]
        panel.canCreateDirectories = true
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data: Data
                    if bookmarks {
                        data = Data(Self.bookmarksHTML(self.session.persistent().spaces).utf8)
                    } else {
                        var value = self.session.persistent()
                        value.windows = []
                        value.downloads = []
                        for s in value.spaces.indices {
                            value.spaces[s].permissions = []
                            for t in value.spaces[s].tabs.indices {
                                value.spaces[s].tabs[t].interactionState = nil
                                value.spaces[s].tabs[t].documentState = nil
                            }
                        }
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .millisecondsSince1970
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        data = try encoder.encode(value)
                    }
                    try data.write(to: url, options: .atomic)
                    self.showNotice("Browser data exported")
                } catch { self.showNotice(error.localizedDescription) }
            }
        }
    }
    static func bookmarksHTML(_ spaces: [BrowserSpace]) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var out =
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Lean Bookmarks</TITLE>\n<DL><p>\n"
        for space in spaces {
            out += "<DT><H3 LEAN_SPACE=\"true\">\(escape(space.name))</H3>\n<DL><p>\n"
            func write(_ parent: UUID?, depth: Int) {
                guard depth < 32 else { return }
                for tab in space.tabs where tab.folderID == parent && tab.placement != .current {
                    if let url = tab.savedURL ?? tab.url {
                        out +=
                            "<DT><A HREF=\"\(escape(url.absoluteString))\">\(escape(tab.customTitle ?? tab.title))</A>\n"
                    }
                }
                for folder in space.folders where folder.parentID == parent {
                    out += "<DT><H3>\(escape(folder.title))</H3>\n<DL><p>\n"
                    write(folder.id, depth: depth + 1)
                    out += "</DL><p>\n"
                }
            }
            write(nil, depth: 0)
            out += "</DL><p>\n"
        }
        return out + "</DL><p>\n"
    }
}
