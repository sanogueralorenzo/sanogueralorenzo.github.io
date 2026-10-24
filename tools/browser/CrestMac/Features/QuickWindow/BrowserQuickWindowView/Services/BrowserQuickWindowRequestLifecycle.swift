@MainActor
struct BrowserQuickWindowRequestLifecycle {
    private let currentRequest: (BrowserQuickWindowRequest) -> Bool
    private let replaceRequest: (BrowserQuickWindowRequest, BrowserQuickWindowRequest) -> Bool

    init(
        isCurrent: @escaping (BrowserQuickWindowRequest) -> Bool,
        replace:
            @escaping (
                BrowserQuickWindowRequest,
                BrowserQuickWindowRequest
            ) -> Bool
    ) {
        currentRequest = isCurrent
        replaceRequest = replace
    }

    func isCurrent(_ request: BrowserQuickWindowRequest) -> Bool {
        currentRequest(request)
    }

    func replace(
        _ expected: BrowserQuickWindowRequest,
        with revised: BrowserQuickWindowRequest
    ) -> Bool {
        replaceRequest(expected, revised)
    }

    static var preview: BrowserQuickWindowRequestLifecycle {
        BrowserQuickWindowRequestLifecycle(
            isCurrent: { _ in true },
            replace: { _, _ in true }
        )
    }
}
