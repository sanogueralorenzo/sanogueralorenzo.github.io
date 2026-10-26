import CoreGraphics

extension CGFloat {
    // MARK: - Actions - Accessibility

    /// This spatial scale, or no scaling at all while the system asks to
    /// reduce motion.
    func unlessReducingMotion(_ reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : self
    }
}
