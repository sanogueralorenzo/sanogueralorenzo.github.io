import SwiftUI

struct BrowserWebKitFeatureFlagSettingsPane: View {
    let store: BrowserWebKitFeatureFlagStore

    @Environment(\.browserSettingsTabState) private var tabState
    @State private var localFilter = BrowserWebKitFeatureFlagFilter()
    private var filter: BrowserWebKitFeatureFlagFilter {
        get { tabState?.featureFilter ?? localFilter }
        nonmutating set {
            if let tabState { tabState.featureFilter = newValue } else { localFilter = newValue }
        }
    }
    @State private var showsResetConfirmation = false

    var body: some View {
        Group {
            if let availabilityFailure = store.availabilityFailure {
                ContentUnavailableView(
                    "Feature Flags Unavailable",
                    systemImage: "flag.slash",
                    description: Text(availabilityFailure)
                )
            } else {
                content
            }
        }
        .confirmationDialog(
            "Reset every WebKit feature flag?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Feature Flags", role: .destructive) {
                store.resetAll()
            }
        } message: {
            Text(
                "Crest will restore its performance defaults and stop overriding every other WebKit feature."
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserWebKitPerformanceSettings(store: store)

            if store.requiresRestart {
                Label(
                    "Restart Crest to apply these changes.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("webkit-feature-restart-notice")
            }

            BrowserWebKitFeatureFlagControls(
                filter: Binding(get: { filter }, set: { filter = $0 }),
                statuses: store.availableStatuses,
                categories: store.availableCategories,
                canReset: store.hasOverrides,
                requestReset: { showsResetConfirmation = true }
            )

            BrowserWebKitFeatureFlagList(
                groups: groups,
                searchText: filter.searchText,
                store: store
            )

            Text(resultSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: BrowserSettingsLayout.formColumnWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 20)
        .padding(.horizontal, BrowserSettingsLayout.formMinimumInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var groups: [BrowserWebKitFeatureFlagGroup] {
        filter.groups(from: store.features, overrides: store.overrides)
    }

    private var resultSummary: String {
        let visibleCount = groups.reduce(0) { $0 + $1.flags.count }
        let overrideCount = store.activeOverrideCount
        return "Showing \(visibleCount) of \(store.features.count) flags · \(overrideCount) changed"
    }
}

private struct BrowserWebKitPerformanceSettings: View {
    @Bindable var store: BrowserWebKitFeatureFlagStore

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                inactiveSchedulingPolicyPicker

                if store.canConfigureAllow120FPS {
                    Toggle("Allow 120 FPS", isOn: $store.allows120FPS)
                        .accessibilityIdentifier("webkit-performance-allow-120-fps")
                }
            }
            .padding(CrestSpacing.extraSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Performance")
        }
        .accessibilityIdentifier("webkit-performance-settings")
    }

    private var inactiveSchedulingPolicyPicker: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Picker(
                "Background tab activity",
                selection: Binding(
                    get: { store.inactiveSchedulingPolicy },
                    set: { store.setInactiveSchedulingPolicy($0) }
                )
            ) {
                Text("Suspend").tag(BrowserInactiveSchedulingPolicy.suspend)
                Text("Throttle").tag(BrowserInactiveSchedulingPolicy.throttle)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "webkit-performance-background-tab-activity"
            )

            Text("Throttle keeps background tabs working and uses more power. Applies to new tabs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
