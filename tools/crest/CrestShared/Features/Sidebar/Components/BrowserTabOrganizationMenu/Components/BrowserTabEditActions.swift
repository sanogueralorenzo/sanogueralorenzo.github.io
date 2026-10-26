import SwiftUI

struct BrowserTabEditActions: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let restoreSavedLocation: (() -> Void)?
    let performIfCurrent: (() -> Void) -> Void
    let replaceSavedLocation: () -> Void
    let clearIcon: () -> Void
    let changeIcon: () -> Void

    var body: some View {
        if tab.supportsSavedLocationEditing {
            Menu("Edit Tab", systemImage: "pencil") {
                Group {
                    Button(
                        "Replace with Current URL",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        performIfCurrent(replaceSavedLocation)
                    }
                    .disabled(!tab.isAwayFromSavedAddress)

                    Button(
                        "Return to Saved URL",
                        systemImage: "arrow.uturn.backward"
                    ) {
                        performIfCurrent { restoreSavedLocation?() }
                    }
                    .disabled(
                        !tab.isAwayFromSavedAddress
                            || restoreSavedLocation == nil
                    )

                    Divider()
                    iconActions
                }
                .crestMenuActionLabelStyle()
            }
        } else {
            iconActions
        }
    }

    private var iconActions: some View {
        BrowserTabIconActions(
            tab: tab,
            favicons: favicons,
            isLoaded: isLoaded,
            pullNewIcon: pullNewIcon,
            performIfCurrent: performIfCurrent,
            clearIcon: clearIcon,
            changeIcon: changeIcon
        )
    }
}
