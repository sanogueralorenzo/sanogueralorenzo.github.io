import SwiftUI

/// One search provider in Settings, collapsed to its icon, name, main shortcut
/// and the switch that offers a built-in to Tab. Clicking anywhere else on the
/// row opens it to its options and the buttons that edit or remove it. The
/// default search stays on; a provider the person added is always on.
struct BrowserSearchProviderRow: View {
    let provider: SearchProvider
    let catalog: BrowserSearchCatalog
    var profileID: UUID? = nil
    @Binding var isExpanded: Bool
    let edit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        summary
        if isExpanded {
            if let builtIn = provider.builtIn {
                ForEach(builtIn.options, id: \.self) { option in
                    BrowserSearchProviderOptionRow(option: option, provider: builtIn, catalog: catalog)
                }
            }
            actions
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: CrestSpacing.small) {
            Button(action: toggleExpanded) {
                HStack(spacing: CrestSpacing.small) {
                    CrestFormDisclosureChevron()
                        .rotationEffect(chevronRotation)
                        .frame(width: BrowserSearchProviderOptionRowMetrics.chevronWidth)
                    BrowserSearchProviderIcon(
                        provider: provider, profileID: profileID, size: BrowserSearchProviderOptionRowMetrics.iconSize)
                    Text(verbatim: provider.title)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: CrestSpacing.small)
                    if let shortcut = provider.shortcuts.first {
                        Text(verbatim: shortcut)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityHint(isExpanded ? Text("Hides its options") : Text("Shows its options"))

            if let builtIn = provider.builtIn {
                Toggle(isOn: enabled(builtIn)) {
                    Text(verbatim: provider.title)
                }
                .labelsHidden()
                .disabled(provider == catalog.defaultProvider)
            }
        }
        .contextMenu {
            Button("Edit…", action: edit)
            if let id = provider.customID {
                Button("Remove", role: .destructive) { catalog.remove(id) }
            }
        }
        .accessibilityIdentifier("search-provider-\(provider.name)")
    }

    /// The chevron points forward while the row is closed and down once open,
    /// whichever way the language reads.
    private var chevronRotation: Angle {
        guard isExpanded else { return .zero }
        return .degrees(layoutDirection == .rightToLeft ? -90 : 90)
    }

    private func toggleExpanded() {
        withAnimation(
            Animation.snappy(duration: CrestMotion.disclosureTransition).unlessReducingMotion(reduceMotion)
        ) {
            isExpanded.toggle()
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: CrestSpacing.small) {
            Button(provider.builtIn == nil ? "Edit…" : "Edit Shortcuts…", action: edit)
                .accessibilityIdentifier("edit-search-provider-\(provider.name)")
            if let id = provider.customID {
                Button("Remove", role: .destructive) { catalog.remove(id) }
                    .accessibilityIdentifier("remove-search-provider-\(provider.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, BrowserSearchProviderOptionRowMetrics.indent)
    }

    private func enabled(_ builtIn: BuiltInSearchProvider) -> Binding<Bool> {
        Binding {
            catalog.isEnabled(provider)
        } set: {
            catalog.setEnabled(builtIn, $0)
        }
    }
}
