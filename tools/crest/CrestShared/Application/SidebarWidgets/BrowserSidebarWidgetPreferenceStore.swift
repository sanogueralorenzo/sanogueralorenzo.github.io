import Foundation
import Observation

protocol BrowserSidebarWidgetPreferencePersisting: AnyObject {
    func loadDisabledKindIdentifiers() -> Set<String>
    func saveDisabledKindIdentifiers(_ identifiers: Set<String>)
}

final class UserDefaultsBrowserSidebarWidgetPreferencePersistence:
    BrowserSidebarWidgetPreferencePersisting
{
    static let key = "crest.sidebar-widgets.disabled-kind-identifiers"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDisabledKindIdentifiers() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func saveDisabledKindIdentifiers(_ identifiers: Set<String>) {
        defaults.set(identifiers.sorted(), forKey: Self.key)
    }
}

final class InMemoryBrowserSidebarWidgetPreferencePersistence:
    BrowserSidebarWidgetPreferencePersisting
{
    private var disabledKindIdentifiers: Set<String>

    init(disabledKindIdentifiers: Set<String> = []) {
        self.disabledKindIdentifiers = disabledKindIdentifiers
    }

    func loadDisabledKindIdentifiers() -> Set<String> {
        disabledKindIdentifiers
    }

    func saveDisabledKindIdentifiers(_ identifiers: Set<String>) {
        disabledKindIdentifiers = identifiers
    }
}

@MainActor
protocol BrowserSidebarWidgetPreferenceObserving: AnyObject {
    func sidebarWidgetPreferencesDidChange()
}

/// The device-local widget visibility choice shared by every Space, profile,
/// and window. Stable kind identifiers are persisted independently of the
/// localized labels that Settings presents.
@Observable
@MainActor
final class BrowserSidebarWidgetPreferenceStore {
    static let shared = launch(environment: .current)

    private(set) var disabledKindIdentifiers: Set<String>

    @ObservationIgnored private let persistence: any BrowserSidebarWidgetPreferencePersisting
    @ObservationIgnored private let observers = NSHashTable<AnyObject>.weakObjects()

    init(persistence: any BrowserSidebarWidgetPreferencePersisting) {
        self.persistence = persistence
        disabledKindIdentifiers = persistence.loadDisabledKindIdentifiers()
    }

    static func launch(
        environment: BrowserLaunchEnvironment,
        productionDefaults: UserDefaults = .standard
    ) -> BrowserSidebarWidgetPreferenceStore {
        guard environment.requiresIsolation else {
            return BrowserSidebarWidgetPreferenceStore(
                persistence: UserDefaultsBrowserSidebarWidgetPreferencePersistence(
                    defaults: productionDefaults
                )
            )
        }
        guard
            let isolationID = environment.persistentIsolationID,
            let defaults = UserDefaults(
                suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                    isolationID: isolationID
                )
            )
        else {
            return BrowserSidebarWidgetPreferenceStore(
                persistence: InMemoryBrowserSidebarWidgetPreferencePersistence()
            )
        }
        return BrowserSidebarWidgetPreferenceStore(
            persistence: UserDefaultsBrowserSidebarWidgetPreferencePersistence(
                defaults: defaults
            )
        )
    }

    func isEnabled(_ kindID: BrowserSidebarWidgetKindID) -> Bool {
        !disabledKindIdentifiers.contains(kindID.rawValue)
    }

    func setEnabled(
        _ isEnabled: Bool,
        for kindID: BrowserSidebarWidgetKindID
    ) {
        var revised = disabledKindIdentifiers
        if isEnabled {
            revised.remove(kindID.rawValue)
        } else {
            revised.insert(kindID.rawValue)
        }
        guard revised != disabledKindIdentifiers else { return }
        disabledKindIdentifiers = revised
        persistence.saveDisabledKindIdentifiers(revised)
        notifyObservers()
    }

    func register(_ observer: any BrowserSidebarWidgetPreferenceObserving) {
        observers.add(observer)
    }

    private func notifyObservers() {
        for case let observer as BrowserSidebarWidgetPreferenceObserving in observers.allObjects {
            observer.sidebarWidgetPreferencesDidChange()
        }
    }
}
