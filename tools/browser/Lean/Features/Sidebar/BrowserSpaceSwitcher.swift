import SwiftUI

struct BrowserSpaceSwitcher: View {
    let store: BrowserStore
    let edit: (BrowserSpace?) -> Void
    @State private var firstVisible = 0
    private var spaces: [BrowserSpace] { store.session.spaces }
    private var width: CGFloat { min(max(CGFloat(spaces.count) * 28 + 4, 56), 100) }
    private var overflows: Bool { CGFloat(spaces.count) * 28 + 4 > width }

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if overflows { scrollButton(forward: false, reader: reader) }
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(spaces) { space in
                            Button {
                                store.selectSpace(space.id)
                            } label: {
                                Circle().fill(Color.space(space.color)).frame(width: 12, height: 12)
                                    .frame(width: 28, height: 20)
                                    .background {
                                        if store.activeSpace.id == space.id { Capsule().fill(.primary.opacity(0.12)) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(space.name)
                            .accessibilityAddTraits(store.activeSpace.id == space.id ? .isSelected : [])
                            .help(space.name)
                            .contextMenu {
                                Button("New Space") { edit(nil) }
                                Button("Edit Space") { edit(space) }
                                Button("Delete Space", role: .destructive) { store.deleteSpace(space.id) }
                                    .disabled(!space.isPrivate && spaces.filter { !$0.isPrivate }.count == 1)
                            }
                            .onDrag { store.dragProvider(space: space.id) }
                            .modifier(BrowserDropArea(store: store, spaceID: space.id))
                            .id(space.id)
                        }
                    }.padding(2).frame(minWidth: overflows ? 0 : width, alignment: .center)
                }
                .scrollIndicators(.never).scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onScrollGeometryChange(for: Int.self) { geometry in
                    Int(max(0, geometry.contentOffset.x) / 28)
                } action: { _, index in
                    firstVisible = index
                }
                if overflows { scrollButton(forward: true, reader: reader) }
            }
            .frame(width: width, height: 24)
            .background(LeanColor.hover, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false) }
            .contextMenu { Button("New Space") { edit(nil) } }
            .onChange(of: store.activeSpace.id) { _, id in reader.scrollTo(id, anchor: .center) }
        }
    }

    private func scrollButton(forward: Bool, reader: ScrollViewProxy) -> some View {
        Button {
            firstVisible = min(max(firstVisible + (forward ? 1 : -1), 0), max(0, spaces.count - 2))
            reader.scrollTo(spaces[firstVisible].id, anchor: .leading)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? "Show Next Spaces" : "Show Previous Spaces")
        .disabled(forward ? firstVisible >= spaces.count - 2 : firstVisible == 0)
    }
}
