import WebKit

struct BrowserWebKitPreferences: Codable, Equatable {
    enum InactiveSchedulingPolicy: String, Codable, CaseIterable, Identifiable {
        case suspend, throttle
        var id: Self { self }
        var webKitValue: WKPreferences.InactiveSchedulingPolicy {
            self == .suspend ? .suspend : .throttle
        }
    }
    var overrides: [String: BrowserWebKitFeatureFlagOverride] = [:]
    var inactiveSchedulingPolicy = InactiveSchedulingPolicy.suspend
}

extension BrowserStore {
    static let preferPageRenderingUpdatesNear60FPSKey = "PreferPageRenderingUpdatesNear60FPSEnabled"
    var webKitSettings: BrowserWebKitPreferences { preferences.webKit ?? BrowserWebKitPreferences() }
    var webKitFeatures: BrowserWebKitFeatureFlagRegistry { owner.webKitFeatures }
    var webKitDefaultOverrides: [String: BrowserWebKitFeatureFlagOverride] {
        webKitFeatures.features.contains { $0.key == Self.preferPageRenderingUpdatesNear60FPSKey }
            ? [Self.preferPageRenderingUpdatesNear60FPSKey: .enabled] : [:]
    }
    var webKitOverrides: [String: BrowserWebKitFeatureFlagOverride] {
        webKitDefaultOverrides.merging(webKitSettings.overrides) { _, selected in selected }
    }
    var hasWebKitOverrides: Bool { webKitOverrides != webKitDefaultOverrides }
    var changedWebKitFlagCount: Int {
        webKitFeatures.features.filter {
            webKitOverrides[$0.key] != nil && webKitOverrides[$0.key] != webKitDefaultOverrides[$0.key]
        }.count
    }
    var canConfigure120FPS: Bool { webKitDefaultOverrides[Self.preferPageRenderingUpdatesNear60FPSKey] != nil }
    var allows120FPS: Bool { webKitOverrides[Self.preferPageRenderingUpdatesNear60FPSKey] == .disabled }

    func configureWebKit(_ preferences: WKPreferences) {
        preferences.inactiveSchedulingPolicy = webKitSettings.inactiveSchedulingPolicy.webKitValue
        webKitFeatures.apply(webKitOverrides, to: preferences)
    }
    func setWebKitOverride(_ value: BrowserWebKitFeatureFlagOverride?, for flag: BrowserWebKitFeatureFlag) {
        guard webKitFeatures.features.contains(where: { $0.key == flag.key }) else { return }
        let resolved = value ?? webKitDefaultOverrides[flag.key]
        guard webKitOverrides[flag.key] != resolved else { return }
        updateWebKit { $0.overrides[flag.key] = resolved }
    }
    func setAllows120FPS(_ value: Bool) {
        guard canConfigure120FPS,
            let flag = webKitFeatures.features.first(where: { $0.key == Self.preferPageRenderingUpdatesNear60FPSKey })
        else { return }
        setWebKitOverride(value ? .disabled : .enabled, for: flag)
    }
    func setInactiveSchedulingPolicy(_ value: BrowserWebKitPreferences.InactiveSchedulingPolicy) {
        guard webKitSettings.inactiveSchedulingPolicy != value else { return }
        updateWebKit { $0.inactiveSchedulingPolicy = value }
    }
    func resetWebKitFlags() {
        guard hasWebKitOverrides else { return }
        updateWebKit { $0.overrides = [:] }
    }
    private func updateWebKit(_ update: (inout BrowserWebKitPreferences) -> Void) {
        var next = webKitSettings
        update(&next)
        updatePreferences { $0.webKit = next }
        owner.webKitFlagsRequireRestart = true
    }
}
