import Dispatch
import Foundation

extension BrowserFaviconStoring {
    /// Stores that finish their work before returning have nothing to flush.
    func flushPendingWrites() async {}
}
