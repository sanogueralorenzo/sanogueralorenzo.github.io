struct MobileTransientBrowsingPresentation: Equatable {
    // MARK: - Variables

    let request: any MobileBrowserTransientRequest
    let phase: BrowserPeekPresentationPhase

    // MARK: - Actions - Identity

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase && lhs.request.matches(rhs.request)
    }
}
