import SwiftUI

/// App-wide chrome choices. Presentation never changes browsing ownership.
struct BrowserChromeAppearance: Equatable {
    var sidebarOnRight = false
    var borderWidth: Double = defaultBorderWidth
    /// The radius of the rounded corners of the window the page sits in. A
    /// full-screen window has none, and only the Mac measures its window.
    var windowCornerRadius: CGFloat?

    static let defaultBorderWidth: Double = 8
    static let borderWidthRange: ClosedRange<Double> = 0...10

    init(
        sidebarOnRight: Bool = false, borderWidth: Double = defaultBorderWidth, windowCornerRadius: CGFloat? = nil
    ) {
        self.sidebarOnRight = sidebarOnRight
        self.borderWidth = borderWidth
        self.windowCornerRadius = windowCornerRadius
    }

    init(sidebarOnRight: Bool = false, borderless: Bool) {
        self.init(sidebarOnRight: sidebarOnRight, borderWidth: borderless ? 0 : Self.defaultBorderWidth)
    }

    var frameWidth: CGFloat {
        CGFloat(
            borderWidth.isFinite ? min(max(borderWidth, 0), Self.borderWidthRange.upperBound) : Self.defaultBorderWidth)
    }
    var borderless: Bool { frameWidth == 0 }
    var seamWidth: CGFloat { BrowserChromeLayout.pageBrandSeamWidth * frameWidth / Self.defaultBorderWidth }
    var pageCornerRadius: CGFloat { borderless ? 0 : framedPageCornerRadius }

    /// The corner of a page inside the frame. It is concentric with the
    /// window's corner, so the frame keeps its width around the corner rather
    /// than pinching there; without a window corner to follow, the page keeps
    /// Crest's own radius.
    var framedPageCornerRadius: CGFloat {
        guard let windowCornerRadius else { return BrowserChromeLayout.pageCornerRadius }
        return max(0, windowCornerRadius - frameWidth)
    }

    /// The window's corner radius, read from the container corner insets of a
    /// view that reaches the bottom of the window. The bottom corners stand for
    /// the window: the top leading one also makes room for the window controls.
    static func windowCornerRadius(from insets: RectangleCornerInsets) -> CGFloat? {
        let radius = max(
            min(insets.bottomLeading.width, insets.bottomLeading.height),
            min(insets.bottomTrailing.width, insets.bottomTrailing.height)
        )
        return radius > 0 ? radius : nil
    }

    func sidebarEdge(in direction: LayoutDirection) -> HorizontalEdge {
        sidebarOnRight == (direction == .leftToRight) ? .trailing : .leading
    }

    static func contentInsets(for rect: CGRect, in size: CGSize, direction: LayoutDirection) -> EdgeInsets {
        let left = max(0, rect.minX)
        let right = max(0, size.width - rect.maxX)
        return EdgeInsets(
            top: max(0, rect.minY),
            leading: direction == .leftToRight ? left : right,
            bottom: max(0, size.height - rect.maxY),
            trailing: direction == .leftToRight ? right : left
        )
    }

    func pageInsets(docked: Bool, direction: LayoutDirection) -> EdgeInsets {
        guard !borderless else { return EdgeInsets() }
        let edge = sidebarEdge(in: direction)
        return EdgeInsets(
            top: frameWidth,
            leading: docked && edge == .leading ? 0 : frameWidth,
            bottom: frameWidth,
            trailing: docked && edge == .trailing ? 0 : frameWidth
        )
    }
}

@MainActor
enum BrowserChromeAppearancePreference {
    static let sidebarOnRightKey = "crest.appearance.sidebar-on-right"
    static let borderWidthKey = "crest.appearance.window-border-width"
    static let borderlessKey = "crest.appearance.borderless"
    static let defaults = defaults(for: .current)

    static func defaults(for environment: BrowserLaunchEnvironment) -> UserDefaults {
        let defaults: UserDefaults
        if environment.requiresIsolation {
            let id = environment.persistentIsolationID ?? "ephemeral-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: id))!
        } else {
            defaults = .standard
        }
        migrateLegacyMobilePreference(in: defaults)
        migrateBorderWidth(in: defaults)
        return defaults
    }
}

extension BrowserChromeAppearancePreference {
    static func migrateBorderWidth(in defaults: UserDefaults) {
        guard defaults.object(forKey: borderWidthKey) == nil else { return }
        defaults.set(
            defaults.bool(forKey: borderlessKey) ? 0 : BrowserChromeAppearance.defaultBorderWidth,
            forKey: borderWidthKey
        )
    }

    static func migrateLegacyMobilePreference(in defaults: UserDefaults) {
        let legacyKey = "crest.sidebar.collapsed.fullscreen.mobile"
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.object(forKey: borderlessKey) == nil {
            defaults.set(defaults.bool(forKey: legacyKey), forKey: borderlessKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}

extension EnvironmentValues {
    @Entry var browserChromeAppearance = BrowserChromeAppearance()
}
