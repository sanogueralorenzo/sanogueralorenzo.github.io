import WebKit

@MainActor
enum BrowserWebKitDefaults {
    static func apply(to preferences: WKPreferences) {
        preferences.inactiveSchedulingPolicy = .suspend

        // Crest enables this preference; every other feature keeps WebKit's default.
        let featuresSelector = NSSelectorFromString("_features")
        let setterSelector = NSSelectorFromString("_setEnabled:forFeature:")
        let keySelector = NSSelectorFromString("key")
        let hiddenSelector = NSSelectorFromString("isHidden")
        let preferencesClass: AnyObject = WKPreferences.self as AnyObject
        guard preferencesClass.responds(to: featuresSelector),
            preferences.responds(to: setterSelector),
            let features = preferencesClass.perform(featuresSelector)?.takeUnretainedValue() as? NSArray
        else { return }
        for case let feature as NSObject in features {
            guard feature.responds(to: keySelector), feature.responds(to: hiddenSelector),
                feature.perform(keySelector)?.takeUnretainedValue() as? String
                    == "PreferPageRenderingUpdatesNear60FPSEnabled"
            else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            let isHidden = unsafeBitCast(feature.method(for: hiddenSelector), to: Getter.self)
            guard !isHidden(feature, hiddenSelector) else { return }
            typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
            let setter = unsafeBitCast(preferences.method(for: setterSelector), to: Setter.self)
            setter(preferences, setterSelector, true, feature)
            return
        }
    }
}
