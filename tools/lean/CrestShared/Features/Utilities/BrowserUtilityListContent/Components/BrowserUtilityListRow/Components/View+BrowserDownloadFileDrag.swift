import SwiftUI

extension View {
    /// On the Mac, lets a finished download's row be dragged out of the
    /// sidebar as its file, the way Finder hands a file to another window or
    /// app: what travels is the file itself, under its Finder icon and name,
    /// so dropping it in a folder copies it and dropping it on an app opens it
    /// there. Touch rows hand a file on through Share and Save to Files
    /// instead, so they are not drag sources.
    func browserDownloadFileDrag(_ download: DownloadState) -> some View {
        #if os(macOS)
            modifier(BrowserDownloadFileDragSource(download: download))
        #else
            self
        #endif
    }
}

#if os(macOS)
    /// A download without a finished file on disk, or whose file the system
    /// will not offer, is not a drag source at all; the row stays a plain
    /// button rather than starting a drag that could deliver nothing.
    private struct BrowserDownloadFileDragSource: ViewModifier {
        let download: DownloadState

        @ViewBuilder
        func body(content: Content) -> some View {
            if let fileURL, let provider = NSItemProvider(contentsOf: fileURL) {
                content
                    .onDrag {
                        provider
                    } preview: {
                        BrowserDownloadFileDragPreview(fileURL: fileURL)
                    }
            } else {
                content
            }
        }

        /// The finished file, where it still stands at its destination.
        private var fileURL: URL? {
            guard download.phase.isComplete,
                let destinationURL = download.destinationURL,
                destinationURL.isFileURL,
                FileManager.default.fileExists(atPath: destinationURL.path)
            else { return nil }
            return destinationURL
        }
    }

    /// What follows the pointer: the file as Finder shows it.
    private struct BrowserDownloadFileDragPreview: View {
        let fileURL: URL

        var body: some View {
            HStack(spacing: CrestSpacing.small) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                Text(fileURL.lastPathComponent)
                    .lineLimit(1)
            }
            .padding(.horizontal, CrestSpacing.medium)
            .padding(.vertical, CrestSpacing.small)
            .background {
                CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact, style: .continuous))
            }
        }
    }
#endif
