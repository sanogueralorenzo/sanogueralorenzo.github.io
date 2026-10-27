import SwiftUI

struct SpaceEditor: View {
    let space: BrowserSpace?
    let store: BrowserStore
    let dismiss: () -> Void
    @State private var name = ""
    @State private var color = 0
    @State private var isPrivate = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(space == nil ? "New Space" : "Edit Space").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(save)
            HStack(spacing: 14) {
                ForEach(0..<6) { index in
                    Button {
                        color = index
                    } label: {
                        Circle().fill(Color.space(index)).frame(width: 22, height: 22)
                            .padding(4).overlay { if color == index { Circle().stroke(.primary, lineWidth: 1) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SpaceColors.names[index])
                }
            }
            if space == nil { Toggle("Private Space", isOn: $isPrivate) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 360)
        .onAppear {
            name = space?.name ?? ""
            color = space?.color ?? 0
            focused = true
        }
    }

    private func save() {
        store.saveSpace(id: space?.id, name: name, color: color, isPrivate: isPrivate)
        dismiss()
    }
}
