import Foundation
import WebKit

@MainActor
protocol BrowserWebKitFeatureFlagRegistryProviding: AnyObject {
    var features: [BrowserWebKitFeatureFlag] { get }
    var availabilityFailure: String? { get }

    func apply(
        _ overrides: [String: BrowserWebKitFeatureFlagOverride],
        to preferences: WKPreferences
    )
}

@MainActor
final class BrowserWebKitFeatureFlagRegistry:
    BrowserWebKitFeatureFlagRegistryProviding
{
    private typealias BooleanGetter =
        @convention(c) (
            AnyObject,
            Selector
        ) -> Bool
    private typealias IntegerGetter =
        @convention(c) (
            AnyObject,
            Selector
        ) -> Int
    private typealias FeatureBooleanGetter =
        @convention(c) (
            AnyObject,
            Selector,
            AnyObject
        ) -> Bool
    private typealias FeatureSetter =
        @convention(c) (
            AnyObject,
            Selector,
            Bool,
            AnyObject
        ) -> Void

    private static let featuresSelector = NSSelectorFromString("_features")
    private static let setEnabledSelector = NSSelectorFromString(
        "_setEnabled:forFeature:"
    )
    private static let isEnabledSelector = NSSelectorFromString(
        "_isEnabledForFeature:"
    )

    private let featureObjectsByKey: [String: NSObject]

    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String?

    init() {
        let preferencesClass: AnyObject = WKPreferences.self as AnyObject
        let probePreferences = WKPreferences()
        guard preferencesClass.responds(to: Self.featuresSelector),
            probePreferences.responds(to: Self.setEnabledSelector),
            probePreferences.responds(to: Self.isEnabledSelector),
            let featureObjects =
                preferencesClass
                .perform(Self.featuresSelector)?
                .takeUnretainedValue() as? NSArray
        else {
            features = []
            featureObjectsByKey = [:]
            availabilityFailure = Self.unavailableMessage
            return
        }

        var resolvedFeatures: [BrowserWebKitFeatureFlag] = []
        var resolvedObjects: [String: NSObject] = [:]
        for case let featureObject as NSObject in featureObjects {
            guard let feature = Self.feature(from: featureObject) else { continue }
            resolvedFeatures.append(feature)
            resolvedObjects[feature.key] = featureObject
        }

        features = resolvedFeatures.sorted {
            if $0.category == $1.category {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.category.rawValue < $1.category.rawValue
        }
        featureObjectsByKey = resolvedObjects
        availabilityFailure = features.isEmpty ? Self.unavailableMessage : nil
    }

    func apply(
        _ overrides: [String: BrowserWebKitFeatureFlagOverride],
        to preferences: WKPreferences
    ) {
        guard preferences.responds(to: Self.setEnabledSelector) else { return }
        let implementation = preferences.method(for: Self.setEnabledSelector)
        let setter = unsafeBitCast(implementation, to: FeatureSetter.self)
        for (key, override) in overrides {
            guard let featureObject = featureObjectsByKey[key] else { continue }
            setter(
                preferences,
                Self.setEnabledSelector,
                override.value,
                featureObject
            )
        }
    }

    func value(
        forKey key: String,
        in preferences: WKPreferences
    ) -> Bool? {
        guard let featureObject = featureObjectsByKey[key],
            preferences.responds(to: Self.isEnabledSelector)
        else { return nil }
        let implementation = preferences.method(for: Self.isEnabledSelector)
        let getter = unsafeBitCast(implementation, to: FeatureBooleanGetter.self)
        return getter(preferences, Self.isEnabledSelector, featureObject)
    }

    private static func feature(
        from object: NSObject
    ) -> BrowserWebKitFeatureFlag? {
        guard let key = stringValue("key", from: object), !key.isEmpty,
            let name = stringValue("name", from: object), !name.isEmpty,
            let defaultValue = booleanValue("defaultValue", from: object),
            let isHidden = booleanValue("isHidden", from: object),
            !isHidden,
            let status = integerValue("status", from: object),
            let category = integerValue("category", from: object)
        else { return nil }

        return BrowserWebKitFeatureFlag(
            key: key,
            name: name,
            details: stringValue("details", from: object) ?? "",
            status: BrowserWebKitFeatureStatus(rawValue: status),
            category: BrowserWebKitFeatureCategory(rawValue: category),
            defaultValue: defaultValue
        )
    }

    private static func stringValue(
        _ selectorName: String,
        from object: NSObject
    ) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    private static func booleanValue(
        _ selectorName: String,
        from object: NSObject
    ) -> Bool? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        let implementation = object.method(for: selector)
        return unsafeBitCast(implementation, to: BooleanGetter.self)(
            object,
            selector
        )
    }

    private static func integerValue(
        _ selectorName: String,
        from object: NSObject
    ) -> Int? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        let implementation = object.method(for: selector)
        return unsafeBitCast(implementation, to: IntegerGetter.self)(
            object,
            selector
        )
    }

    private static let unavailableMessage =
        "This version of WebKit does not expose a compatible feature registry."
}
