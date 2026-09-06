import AppKit
import QuickLookUI

@MainActor
final class ClipboardPreview: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var onError: ((String) -> Void)?
    private let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sh.clipboard.Desktop-preview", isDirectory: true)
    private var previewURL: URL?

    func show(_ clip: Clip) {
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().close() }
        do {
            clear()
            if let url = clip.imageFileURL {
                guard FileManager.default.fileExists(atPath: url.path) else { throw ClipboardSupport.failure("The original image file is no longer available.") }
                previewURL = url
            } else {
                let format = clip.representations?.flatMap({ $0 }).first { [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue].contains($0.type) }
                let encoded = format?.data ?? clip.thumbnail?.split(separator: ",", maxSplits: 1).last.map(String.init)
                guard let encoded, let data = Data(base64Encoded: encoded) else { throw ClipboardSupport.failure("This image has no saved preview data.") }
                try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = previewDirectory.appendingPathComponent(format?.type == NSPasteboard.PasteboardType.tiff.rawValue ? "Image.tiff" : "Image.png")
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                previewURL = url
            }
            RunLoop.main.perform { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.previewURL != nil else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    let panel = QLPreviewPanel.shared()!
                    panel.makeKeyAndOrderFront(nil)
                    if panel.currentController as AnyObject? === self {
                        panel.reloadData(); panel.refreshCurrentPreviewItem()
                    }
                }
            }
        } catch { clear(); onError?(error.localizedDescription) }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewURL != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self; panel.delegate = self
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil; panel.delegate = nil
        clear()
    }
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { MainActor.assumeIsolated { previewURL == nil ? 0 : 1 } }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url = MainActor.assumeIsolated { previewURL }
        return url as NSURL?
    }
    func windowWillClose(_ notification: Notification) { clear() }
    func clear() {
        previewURL = nil
        guard FileManager.default.fileExists(atPath: previewDirectory.path) else { return }
        do { try FileManager.default.removeItem(at: previewDirectory) }
        catch { onError?("Could not remove the temporary preview: \(error.localizedDescription)") }
    }

}
