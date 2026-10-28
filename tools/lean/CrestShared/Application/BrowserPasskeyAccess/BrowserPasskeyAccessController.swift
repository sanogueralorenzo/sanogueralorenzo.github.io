import Observation

@Observable
@MainActor
final class BrowserPasskeyAccessController {
    typealias CapabilityCheck = @MainActor () -> Bool
    typealias DeviceConfigurationCheck =
        @MainActor () -> PasskeyDeviceConfiguration
    typealias AuthorizationCheck = @MainActor () -> PasskeyAuthorizationState
    typealias AuthorizationRequester =
        @MainActor () async -> PasskeyAuthorizationState

    private(set) var status = PasskeyAccessStatus.checking
    private(set) var isRequesting = false

    @ObservationIgnored private let core: CrestCore
    @ObservationIgnored private let capabilityCheck: CapabilityCheck
    @ObservationIgnored private let deviceConfigurationCheck: DeviceConfigurationCheck
    @ObservationIgnored private let authorizationCheck: AuthorizationCheck
    @ObservationIgnored private let authorizationRequester: AuthorizationRequester
    @ObservationIgnored private var authorizationTask: Task<PasskeyAuthorizationState, Never>?

    init(
        core: CrestCore,
        capabilityCheck: @escaping CapabilityCheck =
            BrowserPasskeyAccessSystem.hasManagedCapability,
        deviceConfigurationCheck: @escaping DeviceConfigurationCheck =
            BrowserPasskeyAccessSystem.deviceConfiguration,
        authorizationCheck: @escaping AuthorizationCheck =
            BrowserPasskeyAccessSystem.authorizationState,
        authorizationRequester: @escaping AuthorizationRequester =
            BrowserPasskeyAccessSystem.requestAuthorization
    ) {
        self.core = core
        self.capabilityCheck = capabilityCheck
        self.deviceConfigurationCheck = deviceConfigurationCheck
        self.authorizationCheck = authorizationCheck
        self.authorizationRequester = authorizationRequester
    }

    var canRequestAccess: Bool {
        status.canRequestAccess && !isRequesting
    }

    func refreshStatus() {
        status = evaluatedStatus()
    }

    /// Navigation may check capability, but only an explicit user action may
    /// request browser-wide access to saved accounts. The system can return an
    /// undetermined state again after a relaunch or a keychain availability change.
    func prepareForBrowsing() async {
        refreshStatus()
    }

    func requestAccess() async {
        if let authorizationTask {
            status = evaluatedStatus(authorizationState: await authorizationTask.value)
            return
        }
        guard canRequestAccess else { return }
        isRequesting = true
        defer {
            isRequesting = false
            authorizationTask = nil
        }

        let task = Task { await authorizationRequester() }
        authorizationTask = task
        let authorizationState = await task.value
        status = evaluatedStatus(authorizationState: authorizationState)
    }

    private func evaluatedStatus(
        authorizationState: PasskeyAuthorizationState? = nil
    ) -> PasskeyAccessStatus {
        guard capabilityCheck() else {
            return .managedCapabilityRequired
        }

        // A core that cannot answer keeps checking, which never requests
        // system consent.
        let access = PasskeyAccess(
            hasManagedCapability: true, deviceConfiguration: deviceConfigurationCheck(),
            authorizationState: authorizationState ?? authorizationCheck())
        return (try? core.query(access))?.status ?? .checking
    }
}
