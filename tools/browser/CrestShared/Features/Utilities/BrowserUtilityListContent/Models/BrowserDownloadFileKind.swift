import Foundation

/// What a downloaded file is, by its extension, and the symbol that stands for
/// it.
struct BrowserDownloadFileKind: Hashable, Sendable {
    // MARK: - Static Variables

    static let image = BrowserDownloadFileKind(
        symbol: "photo.fill", extensions: ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "svg"])
    static let pdf = BrowserDownloadFileKind(symbol: "doc.richtext.fill", extensions: ["pdf"])
    static let archive = BrowserDownloadFileKind(
        symbol: "archivebox.fill", extensions: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"])
    static let audio = BrowserDownloadFileKind(
        symbol: "waveform", extensions: ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg"])
    static let video = BrowserDownloadFileKind(
        symbol: "film.fill", extensions: ["mov", "mp4", "m4v", "avi", "mkv", "webm"])
    static let text = BrowserDownloadFileKind(
        symbol: "doc.text.fill", extensions: ["txt", "md", "rtf", "doc", "docx", "pages", "csv"])
    static let diskImage = BrowserDownloadFileKind(symbol: "externaldrive.fill", extensions: ["dmg", "iso", "pkg"])

    /// Any file no other kind names.
    static let document = BrowserDownloadFileKind(symbol: "doc.fill", extensions: [])

    static let all: [BrowserDownloadFileKind] = [image, pdf, archive, audio, video, text, diskImage]

    // MARK: - Variables

    let symbol: String

    /// The lowercase file extensions of this kind.
    let extensions: Set<String>

    // MARK: - Initializers

    private init(symbol: String, extensions: Set<String>) {
        self.symbol = symbol
        self.extensions = extensions
    }

    /// The kind of the file named `filename`, by its extension.
    init(filename: String) {
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        self = Self.all.first { $0.extensions.contains(pathExtension) } ?? .document
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserDownloadFileKind, rhs: BrowserDownloadFileKind) -> Bool {
        lhs.symbol == rhs.symbol
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(symbol)
    }
}
