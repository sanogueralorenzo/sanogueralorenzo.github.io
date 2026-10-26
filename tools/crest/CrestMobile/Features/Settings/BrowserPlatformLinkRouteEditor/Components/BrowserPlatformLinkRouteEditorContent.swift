import SwiftUI

struct BrowserPlatformLinkRouteEditorContent: View {
    let route: LinkRoute
    let spaces: [SpaceModel]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    @FocusState private var isPatternFocused: Bool
    @State private var presentsMatchChoices = false
    @State private var presentsDestinationChoices = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserPlatformLinkRouteLayout.contentSpacing
        ) {
            Toggle(
                "Enabled",
                isOn: binding(
                    route.isEnabled,
                    field: BrowserLinkRouteFieldUpdate.isEnabled
                )
            )
            .frame(
                minHeight: BrowserSettingsControlMetrics.minimumTouchTarget
            )
            .accessibilityIdentifier("route-enabled-\(identifierSuffix)")

            Button {
                presentsMatchChoices = true
            } label: {
                routeChoiceLabel(title: "Match", value: String(localized: route.match.title))
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(route.match.title))
            .accessibilityIdentifier("route-match-\(identifierSuffix)")
            .confirmationDialog(
                "Match",
                isPresented: $presentsMatchChoices,
                titleVisibility: .visible
            ) {
                ForEach(LinkRouteMatch.all, id: \.self) { match in
                    Button(match.title) {
                        update(.match(match))
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            TextField(
                "URL or text",
                text: binding(
                    route.pattern,
                    field: BrowserLinkRouteFieldUpdate.pattern
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.done)
            .focused($isPatternFocused)
            .onSubmit { isPatternFocused = false }
            .frame(
                minHeight: BrowserSettingsControlMetrics.minimumTouchTarget
            )
            .accessibilityIdentifier("route-pattern-\(identifierSuffix)")

            Button {
                presentsDestinationChoices = true
            } label: {
                routeChoiceLabel(title: "Open in", value: destinationName)
            }
            .buttonStyle(.plain)
            .accessibilityValue(destinationName)
            .accessibilityIdentifier("route-destination-\(identifierSuffix)")
            .confirmationDialog(
                "Open in",
                isPresented: $presentsDestinationChoices,
                titleVisibility: .visible
            ) {
                ForEach(spaces) { space in
                    Button(space.settings.name) {
                        update(.destinationSpaceID(space.id))
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            HStack(spacing: CrestSpacing.small) {
                Button("Move Up", systemImage: "chevron.up", action: moveUp)
                    .disabled(!canMoveUp)
                    .accessibilityIdentifier(
                        "route-move-up-\(identifierSuffix)"
                    )
                Button("Move Down", systemImage: "chevron.down", action: moveDown)
                    .disabled(!canMoveDown)
                    .accessibilityIdentifier(
                        "route-move-down-\(identifierSuffix)"
                    )
                Spacer()
                Button(
                    "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    action: delete
                )
                .buttonStyle(BrowserSettingsIconButtonStyle(tint: .red))
                .accessibilityIdentifier("route-delete-\(identifierSuffix)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(BrowserSettingsIconButtonStyle())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-route-\(identifierSuffix)")
    }

    private var identifierSuffix: String {
        route.id.uuidString.lowercased()
    }

    private var destinationName: String {
        spaces.first { $0.id == route.destinationSpaceID }?.settings.name
            ?? "Missing Space"
    }

    private func routeChoiceLabel(
        title: LocalizedStringKey,
        value: String
    ) -> some View {
        HStack(spacing: CrestSpacing.small) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: CrestSpacing.medium)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: BrowserSettingsControlMetrics.minimumTouchTarget
        )
        .contentShape(.rect)
    }

    private func binding<Value>(
        _ value: Value,
        field: @escaping (Value) -> BrowserLinkRouteFieldUpdate
    ) -> Binding<Value> {
        Binding {
            value
        } set: { value in
            update(field(value))
        }
    }
}
