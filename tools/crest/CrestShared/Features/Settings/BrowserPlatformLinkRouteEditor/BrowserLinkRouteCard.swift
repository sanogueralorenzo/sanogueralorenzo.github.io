import SwiftUI

/// A route reads as a condition followed by its destination. The pattern always
/// gets a usable editing width; narrow containers stack the destination below it.
struct BrowserLinkRouteCard: View {
    let route: LinkRoute
    let spaces: [SpaceModel]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    condition
                    Spacer(minLength: 12)
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    condition
                    actions
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 20) {
                    pattern.frame(minWidth: 200)
                    destination.frame(width: 220)
                }
                VStack(alignment: .leading, spacing: 16) {
                    pattern
                    destination
                }
            }
        }
        .padding(16)
        .background(.primary.opacity(0.025), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-route-\(route.id.uuidString.lowercased())")
    }

    private var condition: some View {
        HStack(spacing: 8) {
            Text("When URL").fontWeight(.medium)
            Picker("Match", selection: binding(route.match, field: BrowserLinkRouteFieldUpdate.match)) {
                ForEach(LinkRouteMatch.all, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Toggle("Enabled", isOn: binding(route.isEnabled, field: BrowserLinkRouteFieldUpdate.isEnabled))
                .toggleStyle(.switch).fixedSize()
            Menu {
                Button("Move Up", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                Button("Move Down", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                Divider()
                Button("Delete Route", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(.rect)
            }
            .menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Route actions")
        }
    }

    private var pattern: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL or text").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                // A grouped form shows a field's title as a row label beside
                // it, so the example is a prompt and the label stays hidden.
                TextField(
                    "URL or text", text: binding(route.pattern, field: BrowserLinkRouteFieldUpdate.pattern),
                    prompt: Text("example.com")
                )
                .labelsHidden()
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
            }
            .padding(10)
            .background(BrowserSettingsCanvas.background, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)) }
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open in Space").font(.caption).foregroundStyle(.secondary)
            CrestSpaceMenuPicker(
                "Destination",
                selection: binding(route.destinationSpaceID, field: BrowserLinkRouteFieldUpdate.destinationSpaceID),
                spaces: CrestSpaceIdentity.list(spaces), labelsHidden: true
            )
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
    }

    private func binding<Value>(_ value: Value, field: @escaping (Value) -> BrowserLinkRouteFieldUpdate) -> Binding<
        Value
    > {
        Binding(get: { value }, set: { update(field($0)) })
    }
}
