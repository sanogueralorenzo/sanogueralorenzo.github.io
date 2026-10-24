import SwiftUI

struct BrowserWebKitFeatureFlagControls: View {
    @Binding var filter: BrowserWebKitFeatureFlagFilter

    let statuses: [BrowserWebKitFeatureStatus]
    let categories: [BrowserWebKitFeatureCategory]
    let canReset: Bool
    let requestReset: () -> Void

    var body: some View {
        VStack(spacing: CrestSpacing.small) {
            searchField

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    filters
                    Spacer(minLength: 8)
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    filters
                    actions
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            categoryPicker
            statusPicker
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Toggle("Changed Only", isOn: $filter.showsOnlyChanged).toggleStyle(.switch).fixedSize()
            Button("Reset All", systemImage: "arrow.counterclockwise", action: requestReset)
                .buttonStyle(.bordered)
                .disabled(!canReset)
                .accessibilityIdentifier("webkit-feature-reset-all")
        }
        .fixedSize()
    }

    private var searchField: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search feature flags", text: $filter.searchText)
                .textFieldStyle(.plain)
            if !filter.searchText.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    filter.searchText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CrestSpacing.small)
        .frame(height: 36)
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityIdentifier("webkit-feature-search")
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $filter.category) {
            Text("All Categories").tag(BrowserWebKitFeatureCategory?.none)
            ForEach(categories) { category in
                Text(verbatim: category.title).tag(Optional(category))
            }
        }
        .labelsHidden()
        .accessibilityLabel("Category")
        .frame(width: 160)
    }

    private var statusPicker: some View {
        Picker("Status", selection: $filter.status) {
            Text("All Statuses").tag(BrowserWebKitFeatureStatus?.none)
            ForEach(statuses) { status in
                Text(verbatim: status.title).tag(Optional(status))
            }
        }
        .labelsHidden()
        .accessibilityLabel("Status")
        .frame(width: 150)
    }
}
