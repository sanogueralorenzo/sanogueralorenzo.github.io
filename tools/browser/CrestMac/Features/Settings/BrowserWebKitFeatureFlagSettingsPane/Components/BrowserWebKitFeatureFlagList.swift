import SwiftUI

struct BrowserWebKitFeatureFlagList: View {
    let groups: [BrowserWebKitFeatureFlagGroup]
    let searchText: String
    let store: BrowserWebKitFeatureFlagStore

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.flags) { flag in
                        BrowserWebKitFeatureFlagRow(flag: flag, store: store)
                    }
                } header: {
                    Text(verbatim: group.category.title)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if groups.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No Matching Feature Flags",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .accessibilityIdentifier("webkit-feature-list")
    }
}

private struct BrowserWebKitFeatureFlagRow: View {
    let flag: BrowserWebKitFeatureFlag
    let store: BrowserWebKitFeatureFlagStore

    var body: some View {
        HStack(alignment: .top, spacing: CrestSpacing.medium) {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                HStack(spacing: CrestSpacing.small) {
                    Text(verbatim: flag.name)
                        .fontWeight(.medium)
                    Text(verbatim: flag.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }

                if !flag.details.isEmpty {
                    Text(verbatim: flag.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(verbatim: flag.key)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Feature state", selection: overrideBinding) {
                Text(flag.defaultValue ? "Default (On)" : "Default (Off)")
                    .tag(BrowserWebKitFeatureFlagOverride?.none)
                Text("Enabled")
                    .tag(Optional(BrowserWebKitFeatureFlagOverride.enabled))
                Text("Disabled")
                    .tag(Optional(BrowserWebKitFeatureFlagOverride.disabled))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
            .accessibilityLabel("State for \(flag.name)")
        }
        .padding(.vertical, CrestSpacing.extraSmall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("webkit-feature-\(flag.key)")
    }

    private var overrideBinding: Binding<BrowserWebKitFeatureFlagOverride?> {
        Binding(
            get: { store.override(for: flag) },
            set: { store.setOverride($0, for: flag) }
        )
    }
}
