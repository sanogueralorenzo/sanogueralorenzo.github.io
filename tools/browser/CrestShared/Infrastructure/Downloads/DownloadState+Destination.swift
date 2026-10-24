import Foundation

extension DownloadState {
    /// The file the download writes, once a destination is known.
    var destinationURL: URL? {
        destination.flatMap(URL.init(string:))
    }
}
