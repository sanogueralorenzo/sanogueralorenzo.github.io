import SwiftUI

extension Animation {
    // MARK: - Actions - Accessibility

    /// This animation, or none while the system asks to reduce motion. Crest's
    /// explicit animation transactions go through this; native SwiftUI glass
    /// remains system-owned.
    func unlessReducingMotion(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}
