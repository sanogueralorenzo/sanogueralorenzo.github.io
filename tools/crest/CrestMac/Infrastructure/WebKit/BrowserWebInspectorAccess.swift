import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit

@MainActor
enum BrowserWebInspectorAccess {
    // WebKit's context-menu inspector is exposed as Objective-C SPI rather
    // than Swift API. Resolve it dynamically so an unavailable selector is
    // a disabled action instead of a launch-time linkage failure.
    private static let inspectorSelector = NSSelectorFromString("_inspector")
    private static let showSelector = NSSelectorFromString("show")
    private static let showConsoleSelector = NSSelectorFromString("showConsole")
    private static let showResourcesSelector = NSSelectorFromString("showResources")
    private static let closeSelector = NSSelectorFromString("close")
    private static let isVisibleSelector = NSSelectorFromString("isVisible")
    private static let inspectorWebViewSelector = NSSelectorFromString(
        "inspectorWebView"
    )
    private static let isElementSelectionActiveSelector = NSSelectorFromString(
        "isElementSelectionActive"
    )
    private static let toggleElementSelectionSelector = NSSelectorFromString(
        "toggleElementSelection"
    )
    private static let enableDeveloperExtrasSelector = NSSelectorFromString(
        "_setDeveloperExtrasEnabled:"
    )

    private typealias BooleanSetter =
        @convention(c) (
            AnyObject,
            Selector,
            Bool
        ) -> Void
    private typealias BooleanGetter =
        @convention(c) (
            AnyObject,
            Selector
        ) -> Bool

    @discardableResult
    static func enableDeveloperExtras(in preferences: NSObject) -> Bool {
        guard preferences.responds(to: enableDeveloperExtrasSelector) else {
            return false
        }

        let implementation = preferences.method(for: enableDeveloperExtrasSelector)
        let setter = unsafeBitCast(implementation, to: BooleanSetter.self)
        setter(preferences, enableDeveloperExtrasSelector, true)
        return true
    }

    /// Whether the web view's inspector is showing.
    static func isVisible(inspectorOwner: NSObject) -> Bool {
        inspector(for: inspectorOwner).map { booleanValue(isVisibleSelector, from: $0) } ?? false
    }

    /// Closes the web view's inspector; false when it has none to close.
    static func close(inspectorOwner: NSObject) -> Bool {
        guard let inspector = inspector(for: inspectorOwner), inspector.responds(to: closeSelector) else {
            return false
        }
        inspector.perform(closeSelector)
        return true
    }

    /// Opens the web view's inspector where it last was, or on
    /// `requestedPanel`; false when the web view cannot be inspected.
    static func open(
        _ requestedPanel: InspectorPanel?,
        inspectorOwner: NSObject,
        isInspectable: Bool
    ) -> Bool {
        guard isInspectable,
            let inspector = inspector(for: inspectorOwner)
        else {
            return false
        }
        guard let requestedPanel else {
            guard inspector.responds(to: showSelector) else { return false }
            inspector.perform(showSelector)
            return true
        }

        if requestedPanel != .elements,
            booleanValue(isElementSelectionActiveSelector, from: inspector),
            inspector.responds(to: toggleElementSelectionSelector)
        {
            inspector.perform(toggleElementSelectionSelector)
        }

        let presentationSelector: Selector
        switch requestedPanel {
        case .console:
            presentationSelector = showConsoleSelector
        case .network:
            presentationSelector = showResourcesSelector
        case .elements:
            presentationSelector = showSelector
        }
        guard inspector.responds(to: presentationSelector) else {
            return false
        }
        inspector.perform(presentationSelector)

        if requestedPanel == .network || requestedPanel == .elements {
            showFrontendPanel(requestedPanel, in: inspector)
        }

        if requestedPanel == .elements,
            !booleanValue(isElementSelectionActiveSelector, from: inspector),
            inspector.responds(to: toggleElementSelectionSelector)
        {
            inspector.perform(toggleElementSelectionSelector)
        }
        return true
    }

    private static func inspector(for owner: NSObject) -> NSObject? {
        guard owner.responds(to: inspectorSelector) else { return nil }
        return owner.perform(inspectorSelector)?
            .takeUnretainedValue() as? NSObject
    }

    private static func booleanValue(
        _ selector: Selector,
        from object: NSObject
    ) -> Bool {
        guard object.responds(to: selector) else { return false }
        let implementation = object.method(for: selector)
        let getter = unsafeBitCast(implementation, to: BooleanGetter.self)
        return getter(object, selector)
    }

    private static func showFrontendPanel(
        _ panel: InspectorPanel,
        in inspector: NSObject
    ) {
        guard inspector.responds(to: inspectorWebViewSelector),
            let inspectorWebView =
                inspector
                .perform(inspectorWebViewSelector)?
                .takeUnretainedValue() as? WKWebView
        else { return }

        let functionName = panel.webInspectorFunctionName

        Task { @MainActor in
            for _ in 0..<20 {
                let result = try? await inspectorWebView.evaluateJavaScript(
                    """
                    (() => {
                      const inspector = globalThis.WI;
                      if (typeof inspector?.\(functionName) !== "function") return false;
                      inspector.\(functionName)();
                      return true;
                    })()
                    """
                )
                if result as? Bool == true { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
