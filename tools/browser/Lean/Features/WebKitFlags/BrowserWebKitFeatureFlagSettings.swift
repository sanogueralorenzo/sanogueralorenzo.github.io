import SwiftUI

struct BrowserWebKitFeatureFlagSettings: View {
    let store: BrowserStore
    let back: () -> Void
    @State private var filter = BrowserWebKitFeatureFlagFilter()
    @State private var confirmsReset = false
    private var flags: [BrowserWebKitFeatureFlag] { store.webKitFeatures.features }
    private var groups: [BrowserWebKitFeatureFlagGroup] {
        filter.groups(from: flags, overrides: store.webKitOverrides)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Settings", systemImage: "chevron.left", action: back)
                Text("WebKit Feature Flags").font(.title2)
                Spacer()
            }
            performance
            if store.owner.webKitFlagsRequireRestart {
                Label("Restart Lean to apply these changes.", systemImage: "arrow.clockwise.circle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .accessibilityIdentifier("webkit-feature-restart-notice")
            }
            if let failure = store.webKitFeatures.availabilityFailure {
                ContentUnavailableView("Feature Flags Unavailable", systemImage: "switch.2", description: Text(failure))
            } else {
                controls
                List {
                    ForEach(groups) { group in
                        Section(group.category.title) {
                            ForEach(group.flags) { flag in row(flag) }
                        }
                    }
                }
                .listStyle(.inset).scrollContentBackground(.hidden)
                .overlay {
                    if groups.isEmpty {
                        ContentUnavailableView(
                            "No Matching Feature Flags", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .accessibilityIdentifier("webkit-feature-list")
                Text(
                    "Showing \(groups.reduce(0) { $0 + $1.flags.count }) of \(flags.count) flags · \(store.changedWebKitFlagCount) changed"
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LeanBrandTheme.canvas)
        .confirmationDialog("Reset all WebKit feature flags?", isPresented: $confirmsReset) {
            Button("Reset All Feature Flags", role: .destructive) { store.resetWebKitFlags() }
        } message: {
            Text("Lean will restore its performance defaults and stop overriding every other WebKit feature.")
        }
    }
    private var performance: some View {
        GroupBox("Performance") {
            VStack(alignment: .leading, spacing: 8) {
                Picker(
                    "Background tab activity",
                    selection: Binding(
                        get: { store.webKitSettings.inactiveSchedulingPolicy },
                        set: { store.setInactiveSchedulingPolicy($0) })
                ) {
                    Text("Suspend").tag(BrowserWebKitPreferences.InactiveSchedulingPolicy.suspend)
                    Text("Throttle").tag(BrowserWebKitPreferences.InactiveSchedulingPolicy.throttle)
                }.pickerStyle(.segmented).accessibilityIdentifier("webkit-performance-background-tab-activity")
                Text("Throttle keeps background tabs working and uses more power. Applies to new tabs.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.canConfigure120FPS {
                    Toggle(
                        "Allow 120 FPS", isOn: Binding(get: { store.allows120FPS }, set: { store.setAllows120FPS($0) })
                    )
                    .accessibilityIdentifier("webkit-performance-allow-120-fps")
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            TextField("Search feature flags", text: $filter.searchText)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("webkit-feature-search")
            ViewThatFits(in: .horizontal) {
                HStack {
                    filters
                    actions
                }
                VStack(alignment: .leading) {
                    filters
                    actions
                }
            }
        }
    }
    private var filters: some View {
        HStack {
            Picker("Category", selection: $filter.category) {
                Text("All Categories").tag(BrowserWebKitFeatureCategory?.none)
                ForEach(Array(Set(flags.map(\.category))).sorted { $0.title < $1.title }) {
                    Text($0.title).tag(Optional($0))
                }
            }.labelsHidden().accessibilityLabel("Category").frame(width: 160)
            Picker("Status", selection: $filter.status) {
                Text("All Statuses").tag(BrowserWebKitFeatureStatus?.none)
                ForEach(Array(Set(flags.map(\.status))).sorted { $0.rawValue < $1.rawValue }) {
                    Text($0.title).tag(Optional($0))
                }
            }.labelsHidden().accessibilityLabel("Status").frame(width: 150)
        }
    }
    private var actions: some View {
        HStack {
            Toggle("Changed Only", isOn: $filter.showsOnlyChanged).toggleStyle(.switch).fixedSize()
            Spacer(minLength: 8)
            Button("Reset All", systemImage: "arrow.counterclockwise") { confirmsReset = true }
                .disabled(!store.hasWebKitOverrides).accessibilityIdentifier("webkit-feature-reset-all")
        }
    }
    private func row(_ flag: BrowserWebKitFeatureFlag) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: flag.name).fontWeight(.medium)
                    Text(flag.status.title).font(.caption).foregroundStyle(.secondary)
                }
                if !flag.details.isEmpty {
                    Text(verbatim: flag.details).font(.caption).foregroundStyle(.secondary)
                }
                Text(verbatim: flag.key).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Picker(
                "State for \(flag.name)",
                selection: Binding(
                    get: { store.webKitOverrides[flag.key] }, set: { store.setWebKitOverride($0, for: flag) })
            ) {
                Text(flag.defaultValue ? "Default (On)" : "Default (Off)").tag(BrowserWebKitFeatureFlagOverride?.none)
                Text("Enabled").tag(Optional(BrowserWebKitFeatureFlagOverride.enabled))
                Text("Disabled").tag(Optional(BrowserWebKitFeatureFlagOverride.disabled))
            }.labelsHidden().pickerStyle(.menu).frame(width: 130).accessibilityLabel("State for \(flag.name)")
        }.padding(.vertical, 4).accessibilityElement(children: .contain).accessibilityIdentifier(
            "webkit-feature-\(flag.key)")
    }
}
