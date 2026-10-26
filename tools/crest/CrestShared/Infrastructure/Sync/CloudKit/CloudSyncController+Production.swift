import CloudKit
import Foundation

extension BrowserCloudSyncController {
    convenience init(
        core: CrestCore,
        configuration: BrowserCloudSyncConfiguration? = .configured(),
        defaults: UserDefaults? = nil,
        enabledKey: String = UserDefaultsBrowserCloudSyncPreferences.defaultEnabledKey
    ) {
        if defaults == nil,
            BrowserLaunchEnvironment.current.requiresIsolation
        {
            self.init(
                core: core,
                configuration: nil,
                preferences: InMemoryBrowserCloudSyncPreferences(),
                remoteService: nil,
                transportFactory: nil
            )
            return
        }
        let defaults = defaults ?? .standard
        let preferences = UserDefaultsBrowserCloudSyncPreferences(
            defaults: defaults,
            enabledKey: enabledKey
        )
        let remoteService = configuration.map {
            CloudKitBrowserCloudSyncRemoteService(configuration: $0)
        }
        let transportFactory = configuration.map {
            CloudKitBrowserCloudSyncTransportFactory(
                configuration: $0,
                core: core
            )
        }
        self.init(
            core: core,
            configuration: configuration,
            preferences: preferences,
            legacyState: .production(defaults: defaults),
            remoteService: remoteService,
            transportFactory: transportFactory
        )
        observeAccountChanges(named: .CKAccountChanged)
    }
}
