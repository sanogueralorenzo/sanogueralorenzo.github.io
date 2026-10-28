import SwiftUI

/// Crest isolates nesting feedback so a target change redraws the outline,
/// rather than an expanded folder's contents or a tab's controls.
struct BrowserSidebarNestHighlight: View {
    enum Target {
        case folder(UUID)
        case currentTab(UUID)

        @MainActor func isTargeted(in state: BrowserSidebarReorderState) -> Bool {
            switch self {
            case .folder(let id): state.isTargetedFolder(id)
            case .currentTab(let id): state.isTargetedCurrentTab(id)
            }
        }
    }
    let state: BrowserSidebarReorderState
    let target: Target

    var body: some View {
        if target.isTargeted(in: state) {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            let color = LeanBrandTheme.canvas.opacity(0.72)
            shape.fill(color.opacity(0.14))
                .overlay { shape.strokeBorder(color, lineWidth: 1.5) }
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
