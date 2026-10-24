import SwiftUI

struct BrowserSiteQuickActions: View {
    let page: BrowserPage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            BrowserSiteQuickActionButton(
                title: "Copy Link",
                systemImage: "square.and.arrow.up",
                action: { perform(page.copyDeveloperPageLink) }
            )
            BrowserSiteQuickActionButton(
                title: "Reload",
                systemImage: "arrow.clockwise",
                action: { perform(page.reload) }
            )
            BrowserSiteQuickActionButton(
                title: "Capture",
                systemImage: "camera",
                action: { perform(page.beginRegionCapture) }
            )
            BrowserSiteQuickActionButton(
                title: "Inspect",
                systemImage: "scope",
                action: {
                    perform { page.toggleDeveloperPanel(.elements) }
                }
            )
        }
    }

    private func perform(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}
