@MainActor
protocol BrowserGeolocationServicing: AnyObject {
    func currentAuthorization() -> BrowserSystemAuthorization
    func requestAuthorization() async -> BrowserSystemAuthorization
    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    )
    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    )
    func cancel(identifier: String)
    func cancelAll()
}

extension BrowserGeolocationServicing {
    /// Whether the system lets Crest use the person's location, asking them
    /// when it has not decided and trying `recover` when it refused.
    func systemAuthorizes(recovering recover: @escaping @MainActor () async -> Void) async -> Bool {
        await currentAuthorization().authorizes(
            through: BrowserSystemAuthorizationAccess(
                current: { [self] in currentAuthorization() },
                request: { [self] in await requestAuthorization() },
                recover: recover))
    }
}
