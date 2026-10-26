import SwiftUI
import WebKit

/// The build at a glance at the top of Settings, in the icon the person chose
/// and with the WebKit version the device runs pages in.
struct MobileSettingsBuildHeader: View {
    private static let engine = (Bundle(for: WKWebView.self).infoDictionary?["CFBundleShortVersionString"] as? String)
        .map { "WebKit \($0)" }

    var body: some View {
        BrowserSettingsBuildSummary(engine: Self.engine) {
            BrowserPlatformCurrentAppIcon()
        }
    }
}
