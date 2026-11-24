import SwiftUI

struct SpaceEditor: View {
    let space: BrowserSpace?
    let store: BrowserStore
    let dismiss: () -> Void
    @State private var name = ""
    @State private var isPrivate = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(space == nil ? "New Space" : "Edit Space").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(save)
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
            focused = true
        }
    }

    private func save() {
        store.saveSpace(id: space?.id, name: name, isPrivate: isPrivate)
        dismiss()
    }
}
