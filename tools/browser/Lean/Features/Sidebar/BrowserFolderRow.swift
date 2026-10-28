import SwiftUI

struct BrowserFolderRow: View {
    let folder: BrowserFolder
    let store: BrowserStore
    let depth: Int
    @State private var hovering = false
    private var service: GitHubFolder { store.integration(for: store.activeSpace.id) }

    var body: some View {
        if folder.kind == .regular || !store.activeSpace.isPrivate {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    if store.editingFolderID == folder.id {
                        InlineNameField(
                            title: folder.title,
                            commit: { title in
                                store.updateFolder(folder.id) { $0.title = title.isEmpty ? "New Folder" : title }
                                store.editingFolderID = nil
                            }, cancel: { store.editingFolderID = nil })
                    } else {
                        Button {
                            store.clickFolder(folder.id)
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
                .leanInteractiveSurface(
                    isSelected: false,
                    isHovering: hovering, cornerRadius: 20
                )
                .onHover { hovering = $0 }
                .modifier(
                    BrowserSidebarDragSource(
                        store: store, payload: { store.dragPayload(folder: folder.id) }, title: folder.title,
                        isEnabled: store.editingFolderID != folder.id)
                )
                .modifier(BrowserDropArea(store: store, folder: folder.id))
                .overlay {
                    BrowserSidebarNestHighlight(state: store.sidebarReorder, target: .folder(folder.id))
                }
                .contextMenu {
                    if store.selectedFolders.contains(folder.id) {
                        BrowserSidebarBatchMenu(store: store)
                    } else {
                        Button("Rename Folder") { store.editingFolderID = folder.id }
                        if folder.kind == .regular {
                            Button("New Nested Folder") { store.addFolder(parentID: folder.id) }
                        }
                        if folder.kind == .github {
                            Menu("Live Folder Options") { GitHubFolderMenu(folder: folder, store: store) }
                        }
                        if folder.kind == .regular {
                            Button(folder.placement == .current ? "Move to Saved Tabs" : "Move to Current Tabs") {
                                store.moveFolderLocally(
                                    folder.id, into: nil, placement: folder.placement == .current ? .saved : .current)
                            }
                        }
                        Menu("Move to Folder") {
                            Button("Top Level") { store.moveFolderLocally(folder.id, into: nil) }.disabled(
                                folder.parentID == nil)
                            ForEach(
                                store.activeSpace.folders.filter {
                                    $0.kind == .regular
                                        && !store.descendants(folder.id, in: store.activeSpace).contains($0.id)
                                }
                            ) { target in
                                Button(target.title) { store.moveFolderLocally(folder.id, into: target.id) }.disabled(
                                    folder.parentID == target.id)
                            }
                        }
                        Divider()
                        Button("Delete Folder", role: .destructive) { store.deleteFolder(folder.id) }
                    }
                }
                if folder.isExpanded {
                    if folder.kind == .github {
                        githubItems
                    } else {
                        BrowserSidebarList(
                            store: store, placement: folder.placement ?? .saved, parentID: folder.id, depth: depth + 1)
                    }
                }
            }
            .padding(folder.isExpanded ? 4 : 0)
            .leanInteractiveSurface(
                isSelected: store.selectedFolders.contains(folder.id) && !store.selectionCovers(folder.parentID),
                isHovering: false, cornerRadius: max(0, 20 - CGFloat(depth) * 4),
                selectionEmphasis: store.sidebarKeyboardSelection && store.selectedFolders.contains(folder.id)
            )
            .background(
                LeanBrandTheme.line.opacity(folder.isExpanded ? 0.22 : 0),
                in: RoundedRectangle(cornerRadius: max(0, 20 - CGFloat(depth) * 4))
            )
            .modifier(
                BrowserSidebarReorderItem(
                    store: store, id: folder.id, placement: folder.placement ?? .saved, folderID: folder.parentID))
        }
    }

    private var githubItems: some View {
        VStack(spacing: 2) {
            let tabs = store.activeSpace.tabs.filter { $0.folderID == folder.id }
            if tabs.isEmpty {
                if service.isLoading {
                    ProgressView().controlSize(.small).padding(8)
                } else if !folder.githubOptions.hasFilters {
                    Text("Filter is not set").foregroundStyle(.secondary).padding(8)
                } else if !service.isSignedIn {
                    Button("Connect GitHub") { store.open(URL(string: "https://github.com/pulls")!) }
                        .buttonStyle(.plain).padding(8)
                } else {
                    Text(service.error ?? "No open pull requests").foregroundStyle(.secondary).padding(8)
                }
            }
            ForEach(tabs) { tab in BrowserSidebarItem(tab: tab, store: store, depth: depth + 1).font(.system(size: 13))
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct GitHubFolderMenu: View {
    let folder: BrowserFolder
    let store: BrowserStore

    var body: some View {
        let service = store.integration(for: store.activeSpace.id)
        Text(
            !service.isSignedIn
                ? "Not signed in to GitHub"
                : !folder.githubOptions.hasFilters
                    ? "Filter is not set"
                    : service.error != nil
                        ? "Failed to update"
                        : service.lastFetched.map { "Last fetch: " + $0.formatted(.relative(presentation: .numeric)) }
                            ?? "Not fetched yet"
        ).disabled(true)
        Picker("Fetch Interval", selection: option(\.intervalMinutes)) {
            ForEach([15, 30, 60, 120, 240, 480], id: \.self) { minutes in
                Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) \(minutes == 60 ? "hour" : "hours")").tag(
                    minutes)
            }
        }
        Button("Refresh") { store.integration(for: store.activeSpace.id).requestRefresh() }
        Toggle("Created by Me", isOn: option(\.authorMe))
        Toggle("Assigned to Me", isOn: option(\.assignedMe))
        Toggle("Review Requests", isOn: option(\.reviewRequested))
        Toggle("Include Draft Pull Requests", isOn: option(\.includeDrafts))
        Menu("Repositories") {
            ForEach(store.integration(for: store.activeSpace.id).repositories, id: \.self) { repository in
                Toggle(
                    repository,
                    isOn: Binding(
                        get: {
                            !folder.githubOptions.excludedRepositories.contains {
                                $0.caseInsensitiveCompare(repository) == .orderedSame
                            }
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
