import Observation
import SwiftUI

struct BrowserSettingsTabContent {
    let makeView: @MainActor (BrowserNativeTabRuntime) -> MobileBrowserSettingsView
}

@Observable @MainActor
final class MobileBrowserSettingsState {
    var selection = BrowserSettingsDestination.general {
        didSet { showsDestinationList = false }
    }
    private var showsDestinationList = true
    var searchText = ""
    var path: [BrowserSettingsDestination] = [] {
        didSet {
            if let destination = path.last {
                selection = destination
            } else {
                showsDestinationList = true
            }
        }
    }
    func prepareForEmbeddedPresentation() {
        showsDestinationList = false
    }

    func prepareForSheetPresentation() {
        path = showsDestinationList ? [] : [selection]
    }
}
