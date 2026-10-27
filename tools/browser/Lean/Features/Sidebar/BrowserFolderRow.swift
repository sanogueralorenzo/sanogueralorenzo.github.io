import SwiftUI

struct BrowserFolderRow: View {
    let folder: BrowserFolder
    let store: BrowserStore
    let depth: Int
    @State private var hovering = false
    private var service: GitHubFolder { store.integration(for: store.activeSpace.id) }

    var body: some View {
        if folder.kind == .regular || service.isSignedIn {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    if store.editingFolderID == folder.id {
                        InlineNameField(title: folder.title) { title in
                            store.updateFolder(folder.id) { $0.title = title.isEmpty ? "Folder" : title }
                            store.editingFolderID = nil
                        }
                    } else {
                        Button {
                            store.updateFolder(folder.id) { $0.isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: folder.isExpanded ? "folder.fill" : "folder").frame(width: 28)
                                Text(folder.title).lineLimit(1)
                                Spacer(minLength: 0)
                                if folder.kind == .github {
                                    if service.isLoading {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Text("\(service.items.count)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10).frame(height: SidebarGeometry.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: SidebarGeometry.rowHeight)
                .leanInteractiveSurface(isSelected: false, isHovering: hovering, cornerRadius: 20)
                .onHover { hovering = $0 }
                .onDrag { store.dragProvider(folder: folder.id) }
                .modifier(BrowserDropArea(store: store, folder: folder.id))
                .contextMenu {
                    Button("Rename") { store.editingFolderID = folder.id }
                    if folder.kind == .regular { Button("New Folder") { store.addFolder(parentID: folder.id) } }
                    if folder.kind == .github { GitHubFolderMenu(folder: folder, store: store) }
                    Divider()
                    Button("Delete Folder", role: .destructive) { store.deleteFolder(folder.id) }
                }
                if folder.isExpanded {
                    if folder.kind == .github {
                        githubItems
                    } else {
                        ForEach(store.activeSpace.tabs.filter { $0.folderID == folder.id }) { tab in
                            BrowserSidebarItem(tab: tab, store: store).padding(.leading, 12)
                        }
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 12)
        }
    }

    private var githubItems: some View {
        VStack(spacing: 2) {
            if service.items.isEmpty {
                Text(service.error ?? "No matching pull requests").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
            }
            ForEach(service.items) { item in
                if let tab = store.activeSpace.tabs.first(where: { $0.folderID == folder.id && $0.savedURL == item.url }
                ) {
                    BrowserSidebarItem(tab: tab, store: store).padding(.leading, 12)
                } else {
                    Button {
                        _ = store.open(item.url, placement: .saved, folderID: folder.id)
                    } label: {
                        HStack(spacing: 9) {
                            Circle().fill(.green).frame(width: 6, height: 6).frame(width: 28)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: SidebarGeometry.rowHeight)
                    }
                    .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 20))
                    .padding(.leading, 12)
                }
            }
        }
    }
}

private struct GitHubFolderMenu: View {
    let folder: BrowserFolder
    let store: BrowserStore

    var body: some View {
        Picker("Fetch Interval", selection: option(\.intervalMinutes)) {
            ForEach([15, 30, 60, 120, 240, 480], id: \.self) { minutes in
                Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour(s)").tag(minutes)
            }
        }
        Button("Refresh") { store.integration(for: store.activeSpace.id).requestRefresh() }
        Toggle("Created by Me", isOn: option(\.authorMe))
        Toggle("Assigned to Me", isOn: option(\.assignedMe))
        Toggle("Review Requested", isOn: option(\.reviewRequested))
        Toggle("Include Drafts", isOn: option(\.includeDrafts))
        Menu("Repositories") {
            ForEach(store.integration(for: store.activeSpace.id).repositories, id: \.self) { repository in
                Toggle(
                    repository,
                    isOn: Binding(
                        get: {
                            !folder.githubOptions.excludedRepositories.contains(repository)
                        },
                        set: { included in
                            store.updateFolder(folder.id) { value in
                                value.githubOptions.excludedRepositories.removeAll { $0 == repository }
                                if !included { value.githubOptions.excludedRepositories.append(repository) }
                            }
                            store.integration(for: store.activeSpace.id).requestRefresh()
                        }))
            }
        }
    }

    private func option<Value>(_ keyPath: WritableKeyPath<GitHubLiveFolderOptions, Value>) -> Binding<Value> {
        Binding(
            get: { folder.githubOptions[keyPath: keyPath] },
            set: { value in
                store.updateFolder(folder.id) { $0.githubOptions[keyPath: keyPath] = value }
                store.integration(for: store.activeSpace.id).requestRefresh()
            })
    }
}
