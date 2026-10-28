import CoreGraphics
import Foundation
import Observation

@MainActor
protocol BrowserDefaultPageZoomObserving: AnyObject {
    func defaultPageZoomDidChange(to zoom: CGFloat)
}

protocol BrowserDefaultPageZoomPersisting {
    func load() -> CGFloat?
    func save(_ zoom: CGFloat)
}

final class UserDefaultsBrowserDefaultPageZoomPersistence:
    BrowserDefaultPageZoomPersisting
{
    static let key = "crest.page-zoom.default"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CGFloat? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return CGFloat(defaults.double(forKey: Self.key))
    }

    func save(_ zoom: CGFloat) {
        defaults.set(Double(zoom), forKey: Self.key)
    }
}

final class InMemoryBrowserDefaultPageZoomPersistence:
    BrowserDefaultPageZoomPersisting
{
    private var zoom: CGFloat?

    init(zoom: CGFloat? = nil) {
        self.zoom = zoom
    }

    func load() -> CGFloat? {
        zoom
    }

    func save(_ zoom: CGFloat) {
        self.zoom = zoom
    }
}

/// The one persisted global zoom baseline shared by every browser runtime.
///
/// Pages subscribe weakly so changing Settings can update every resident page
/// without making their lifetimes part of the preference's lifetime. A page with
/// a temporary command override decides for itself whether to adopt the change.
@Observable
@MainActor
final class BrowserDefaultPageZoomStore {
    /// The baseline a page starts at when nothing else is saved.
    nonisolated static let defaultLevel: CGFloat = 1
    /// The baselines a saved preference may hold.
    nonisolated static let defaultRange: ClosedRange<CGFloat> = 0.25...5

    static let shared: BrowserDefaultPageZoomStore = {
        let environment = BrowserLaunchEnvironment.current
        guard environment.requiresIsolation else {
            return BrowserDefaultPageZoomStore(persistence: UserDefaultsBrowserDefaultPageZoomPersistence())
        }
        if let id = environment.persistentIsolationID,
            let defaults = UserDefaults(
                suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: id)
            )
        {
            return BrowserDefaultPageZoomStore(
                persistence: UserDefaultsBrowserDefaultPageZoomPersistence(defaults: defaults)
            )
        }
        return BrowserDefaultPageZoomStore(persistence: InMemoryBrowserDefaultPageZoomPersistence())
    }()

    private var storedDefaultZoom: CGFloat

    @ObservationIgnored private let persistence: any BrowserDefaultPageZoomPersisting
    @ObservationIgnored private let observers = NSHashTable<AnyObject>.weakObjects()

    var defaultZoom: CGFloat {
        get { storedDefaultZoom }
        set { setDefaultZoom(newValue) }
    }

    init(persistence: any BrowserDefaultPageZoomPersisting) {
        self.persistence = persistence
        let persisted = persistence.load()
        let normalized = Self.normalized(
            persisted ?? Self.defaultLevel
        )
        storedDefaultZoom = normalized
        if let persisted,
            persisted != normalized
        {
            persistence.save(normalized)
        }
    }

    /// Preserve the continuous multiplier, bounding only out-of-range values.
    /// Non-finite values fall back to the familiar 100% default.
    nonisolated static func normalized(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return defaultLevel }
        return min(max(proposed, defaultRange.lowerBound), defaultRange.upperBound)
    }

    func register(_ observer: any BrowserDefaultPageZoomObserving) {
        observers.add(observer)
        observer.defaultPageZoomDidChange(to: storedDefaultZoom)
    }

    private func setDefaultZoom(_ proposed: CGFloat) {
        let normalized = Self.normalized(proposed)
        guard normalized != storedDefaultZoom else {
            return
        }
        storedDefaultZoom = normalized
        persistence.save(normalized)
        for observer in observers.allObjects {
            (observer as? any BrowserDefaultPageZoomObserving)?
                .defaultPageZoomDidChange(to: normalized)
        }
    }
}
