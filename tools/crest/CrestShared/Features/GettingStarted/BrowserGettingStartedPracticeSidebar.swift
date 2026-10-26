import SwiftUI

/// The app's real tab rows and actions, bound only to the in-memory practice store.
struct BrowserGettingStartedPracticeSidebar: View {
    let practice: BrowserGettingStartedPractice
    let capabilities: BrowserInteractionCapabilities

    var body: some View {
        let space = practice.space
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    BrowserSpaceCrestIcon(branding: space.settings.look, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice").font(CrestTypography.sans(14, weight: .semibold))
                        Text("Your example Space").font(CrestTypography.sans(10)).foregroundStyle(.secondary)
                    }
                    if capabilities.supportsTouch {
                        Spacer()
                        Menu {
                            Button("New Tab", systemImage: "plus", action: practice.openExampleTab)
                            Button("New Folder", systemImage: "folder.badge.plus") {
                                practice.addFolder(nested: false)
                            }
                            Button("Clean Up Current Tabs", systemImage: "sparkles") {
                                _ = practice.tabActions.clearCurrentTabs()
                            }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Practice Space actions")
                    }
                }.padding(.horizontal, 10).padding(.top, 12)
                if let context = practice.listContext(capabilities: capabilities) {
                    BrowserPinnedTabsDropSection(context: context)
                    Text("Saved").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(
                        .horizontal, 14)
                    BrowserSidebarTabList(
                        context: context, alwaysShowsSavedTabs: true, showsClearAction: true,
                        openNewTab: practice.openExampleTab)
                }
            }.padding(8)
        }
        .environment(practice.sidebarInteraction)
        .browserNativeScrollState(practice.sidebarScroll)
        .scrollIndicators(.automatic)
        .background(CrestBrandTheme.surface)
    }
}
