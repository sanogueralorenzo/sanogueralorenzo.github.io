import SwiftUI

struct BrowserSpaceOrderControls: View {
    let browser: BrowserStore
    let spaceID: UUID?

    var body: some View {
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: spaceID)
        // Separate containers prevent the arrows from merging. A glassEffectUnion
        // here can cycle macOS key-view traversal when a Settings field gains focus.
        HStack(spacing: CrestSpacing.small) {
            GlassEffectContainer {
                BrowserSpaceSettingsGlassButton(title: "Move Up", symbol: "arrow.up", action: actions.moveUp)
                    .disabled(!actions.canMoveUp)
                    .help("Move Up")
                    .accessibilityIdentifier("space-settings-move-up")
            }
            GlassEffectContainer {
                BrowserSpaceSettingsGlassButton(title: "Move Down", symbol: "arrow.down", action: actions.moveDown)
                    .disabled(!actions.canMoveDown)
                    .help("Move Down")
                    .accessibilityIdentifier("space-settings-move-down")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}
