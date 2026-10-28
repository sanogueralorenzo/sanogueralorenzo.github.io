extension BrowserTabDragState {
    /// Whether a drag's source always hears that the drag ended. iOS 27 is the
    /// first release that guarantees it.
    nonisolated static var hasReliableTerminalLifecycle: Bool {
        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                true
            } else {
                false
            }
        #else
            false
        #endif
    }
}
