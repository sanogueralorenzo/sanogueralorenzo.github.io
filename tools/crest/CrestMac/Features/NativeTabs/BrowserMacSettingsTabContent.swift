import SwiftUI

struct BrowserSettingsTabContent {
    let makeView: @MainActor (BrowserNativeTabRuntime) -> BrowserSettingsView
}
