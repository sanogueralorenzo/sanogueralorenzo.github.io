import SwiftUI

struct BrowserExtensionSpaceSelectionList: View {
    let spaces: [BrowserSpaceIdentity]
    @Binding var selection: Set<UUID>

    private var availableIDs: Set<UUID> { Set(spaces.map(\.id)) }
    private var selectedCount: Int { selection.intersection(availableIDs).count }
    private var allSelected: Bool { !spaces.isEmpty && selectedCount == spaces.count }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            if spaces.isEmpty {
                Text(
                    "No other Spaces are available. Unlock a Space to include it; Spaces that already have this extension are excluded."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("\(selectedCount) of \(spaces.count) selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if allSelected {
                            selection.subtract(availableIDs)
                        } else {
                            selection.formUnion(availableIDs)
                        }
                    } label: {
                        if allSelected { Text("Deselect All") } else { Text("Select All") }
                    }
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(spaces) { space in
                            Toggle(
                                isOn: Binding(
                                    get: { selection.contains(space.id) },
                                    set: { selected in
                                        if selected { selection.insert(space.id) } else { selection.remove(space.id) }
                                    }
                                )
                            ) {
                                BrowserSpaceIdentityLabel(space: space, iconSize: 24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, CrestSpacing.medium)
                            if space.id != spaces.last?.id { Divider() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }
        }
    }
}
