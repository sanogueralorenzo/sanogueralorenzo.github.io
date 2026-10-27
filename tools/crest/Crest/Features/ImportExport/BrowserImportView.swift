import SwiftUI
import UniformTypeIdentifiers

struct BrowserImportView: View {
    let store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var spaces: [BrowserSpace] = []
    @State private var selected: Set<UUID> = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Browser Data").font(.title2)
            if spaces.isEmpty {
                Text("Choose a browser or a bookmarks/session file. Passwords and website cookies are not imported.")
                    .foregroundStyle(.secondary)
                ForEach(BrowserImportSource.installed) { source in
                    Button(source.name) { choose(directory: source.directory) }.disabled(loading)
                }
                Button("Choose Files or Folder…") { choose(directory: nil) }.disabled(loading)
            } else {
                List(spaces) { space in
                    Toggle(
                        isOn: Binding(
                            get: { selected.contains(space.id) },
                            set: { if $0 { selected.insert(space.id) } else { selected.remove(space.id) } })
                    ) {
                        Text(space.name)
                        Text("\(space.tabs.count) tabs · \(space.folders.count) folders").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }.frame(height: 260)
            }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                if !spaces.isEmpty {
                    Button("Import Selected Spaces") {
                        do {
                            try store.acceptImport(spaces.filter { selected.contains($0.id) })
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 520)
    }
    private func choose(directory: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = directory
        panel.message = "Choose the browser data folder, bookmarks export, or session file."
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK else { return }
                loading = true
                defer { loading = false }
                do {
                    spaces = try await store.readImportFiles(panel.urls)
                    selected = Set(spaces.map(\.id))
                    error = spaces.isEmpty ? "No supported browsing data was found." : nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct BrowserExportView: View {
    let store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Browser Data").font(.title2)
            Text("Private Spaces, cookies, form contents, download credentials, and website permissions are excluded.")
                .foregroundStyle(.secondary)
            Button("Crest Browser Data") {
                store.saveExport(bookmarks: false)
                dismiss()
            }
            Button("HTML Bookmarks") {
                store.saveExport(bookmarks: true)
                dismiss()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }.padding(24).frame(width: 460)
    }
}
