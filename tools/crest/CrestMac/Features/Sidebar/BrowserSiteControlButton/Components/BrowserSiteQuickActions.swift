import SwiftUI

struct BrowserSiteQuickActions: View {
    let page: BrowserPage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            BrowserSiteQuickActionButton(
                title: "Copy Link",
                systemImage: "square.and.arrow.up",
                action: { perform { page.copyPageLink() } }
            )
            BrowserSiteQuickActionButton(
                title: "Reload",
                systemImage: "arrow.clockwise",
                action: { perform(page.reload) }
            )
            BrowserSiteQuickActionButton(
                title: LocalizedStringKey(page.translation.actionTitle),
                systemImage: "translate",
                action: { perform(page.translation.performAction) }
            )
            .disabled(!page.pageEngine.registration.supports(.translation) || page.readerModeState.isActive)
            .accessibilityValue(page.translation.status)
            .accessibilityIdentifier("site-translation-button")
            .help(page.translation.status.isEmpty ? page.translation.actionTitle : page.translation.status)
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
