import AppKit

extension BrowserStore {
    var sidebarSelectionUnits: [[UUID]] {
        var units: [[UUID]] = []
        var seenSplits = Set<UUID>()
        func append(_ tabs: [BrowserTab]) {
            for tab in tabs {
                if let split = activeSpace.splits.first(where: { $0.tabIDs.contains(tab.id) }) {
                    if seenSplits.insert(split.id).inserted { units.append(split.tabIDs) }
                } else {
                    units.append([tab.id])
                }
            }
        }
        func walk(_ parent: UUID?, _ placement: BrowserTab.Placement, keeping: UUID? = nil) {
            for entry in activeSpace.sidebarEntries(parentID: parent, placement: placement) {
                switch entry.kind {
                case .folder(let folder):
                    let activeInside =
                        selectedTab.map { descendants(folder.id, in: activeSpace).contains($0.folderID ?? UUID()) }
                        ?? false
                    if keeping != nil && !activeInside { continue }
                    units.append([folder.id])
                    if folder.isExpanded && keeping == nil {
                        walk(folder.id, placement)
                    } else if activeInside, let active = selectedTab {
                        walk(folder.id, placement, keeping: active.id)
                    }
                case .tab(let tab):
                    if let keeping, keeping != tab.id { continue }
                    append([tab])
                }
            }
        }
        append(activeSpace.pinnedTabs)
        walk(nil, .saved)
        walk(nil, .current)
        return units
    }

    var selectedSidebarItems: Set<UUID> {
        get { selectedTabs.union(selectedFolders) }
        set {
            selectedFolders = newValue.intersection(activeSpace.folders.map(\.id))
            selectedTabs = newValue.intersection(activeSpace.tabs.map(\.id))
        }
    }
    var selectionRootFolders: [UUID] {
        let roots = Set(
            activeSpace.folders.filter {
                selectedFolders.contains($0.id) && !selectionCovers($0.parentID)
            }.map(\.id))
        return activeSpace.sidebarItemIDs.filter(roots.contains)
    }
    func selectionCovers(_ folderID: UUID?) -> Bool {
        var cursor = folderID
        var visited = Set<UUID>()
        while let id = cursor, visited.insert(id).inserted {
            if selectedFolders.contains(id) { return true }
            cursor = activeSpace.folders.first { $0.id == id }?.parentID
        }
        return false
    }
    var selectedActionTabIDs: [UUID] {
        relatedTabIDs(sidebarOrder.filter { selectedTabs.contains($0.id) || selectionCovers($0.folderID) }.map(\.id))
    }
    var selectedLooseTabIDs: [UUID] {
        relatedTabIDs(sidebarOrder.filter { selectedTabs.contains($0.id) && !selectionCovers($0.folderID) }.map(\.id))
    }
    func clearSidebarSelection() {
        selectedSidebarItems = []
        selectionAnchor = nil
        selectionRangeBase = nil
        sidebarKeyboardSelection = false
    }
    func clickTab(
        _ id: UUID, modifiers: NSEvent.ModifierFlags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    ) {
        clickSidebarItem(id, modifiers: modifiers)
    }
    func clickFolder(
        _ id: UUID, modifiers: NSEvent.ModifierFlags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    ) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            clickSidebarItem(id, modifiers: modifiers)
        } else {
            clearSidebarSelection()
            updateFolder(id) { $0.isExpanded.toggle() }
        }
    }
    private func clickSidebarItem(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        let units = sidebarSelectionUnits
        let command = modifiers.contains(.command)
        selectionFocusedID = id
        if modifiers.contains(.shift), let anchor = selectionAnchor ?? selectedTab?.id,
            let first = units.firstIndex(where: { $0.contains(anchor) }),
            let last = units.firstIndex(where: { $0.contains(id) })
        {
            selectionAnchor = anchor
            if selectionRangeBase == nil { selectionRangeBase = command ? selectedSidebarItems : [] }
            selectedSidebarItems = (selectionRangeBase ?? []).union(
                units[min(first, last)...max(first, last)].flatMap { $0 })
            sidebarKeyboardSelection = true
            window?.makeFirstResponder(nil)
        } else if command {
            selectionRangeBase = nil
            selectionAnchor = id
            let unit = Set(units.first { $0.contains(id) } ?? [id])
            var picks = selectedSidebarItems
            if unit.isSubset(of: picks) { picks.subtract(unit) } else { picks.formUnion(unit) }
            selectedSidebarItems = picks
            sidebarKeyboardSelection = true
            window?.makeFirstResponder(nil)
        } else {
            selectTab(id)
            selectionAnchor = id
            selectionRangeBase = nil
        }
    }
    func actionTabs(_ id: UUID) -> [UUID] {
        selectedTabs.contains(id) || selectionCovers(activeSpace.tabs.first { $0.id == id }?.folderID)
            ? selectedActionTabIDs : relatedTabIDs([id])
    }
    func fileSidebarSelection(as placement: BrowserTab.Placement, folderID: UUID? = nil) {
        moveSidebarItems(
            BrowserDragPayload(
                kind: .tabs, spaceID: activeSpace.id, ids: selectedLooseTabIDs,
                folderIDs: selectionRootFolders, activeTabID: selectedTab?.id),
            to: activeSpace.id, parentID: folderID, placement: placement)
    }

    func deleteSidebarSelection() {
        requestDeleteSidebarItems(selectedActionTabIDs, folders: selectionRootFolders, in: activeSpace.id)
    }

    func requestDeleteSidebarItems(_ tabIDs: [UUID], folders rootIDs: [UUID] = [], in spaceID: UUID) {
        guard !isClosed, let source = session.spaces.first(where: { $0.id == spaceID }),
            Set(tabIDs).isSubset(of: Set(source.tabs.map(\.id))),
            Set(rootIDs).isSubset(of: Set(source.folders.map(\.id)))
        else { return }
        let requested = Set(tabIDs)
        let nested = rootIDs.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1, in: source)) }
        let members = source.tabs.filter { requested.contains($0.id) || $0.folderID.map(nested.contains) == true }
        let tabs = members.map(\.id)
        let tabSet = Set(tabs)
        guard !tabs.isEmpty || !nested.isEmpty else { return }
        Task {
            // A folder edited while its pages answer is a different deletion.
            // Refuse the entire request rather than orphaning or taking new work.
            guard await prepareTabs(tabs), let index = session.spaces.firstIndex(where: { $0.id == spaceID }) else {
                return
            }
            let current = session.spaces[index]
            let currentTabs = Dictionary(uniqueKeysWithValues: current.tabs.map { ($0.id, $0) })
            guard Set(rootIDs).isSubset(of: Set(current.folders.map(\.id))),
                rootIDs.reduce(into: Set<UUID>(), { $0.formUnion(descendants($1, in: current)) }) == nested,
                Set(
                    current.tabs.filter {
                        requested.contains($0.id) || $0.folderID.map(nested.contains) == true
                    }.map(\.id)) == tabSet,
                members.allSatisfy({ original in
                    currentTabs[original.id].map {
                        $0.folderID == original.folderID && $0.placement == original.placement
                    } == true
                })
            else { return }
            for id in tabs { deleteTab(id) }
            if session.spaces[index].folders.contains(where: { nested.contains($0.id) && $0.kind == .github }) {
                session.spaces[index].githubDismissed = true
            }
            session.spaces[index].folders.removeAll { nested.contains($0.id) }
            if activeSpace.id == spaceID {
                selectedTabs.subtract(tabSet)
                selectedFolders.subtract(nested)
                if selectionAnchor.map({ tabSet.contains($0) || nested.contains($0) }) == true {
                    selectionAnchor = nil
                    selectionRangeBase = nil
                }
            }
            changed()
        }
    }
    func handleSidebarSelectionKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard sidebarKeyboardSelection, !(window?.firstResponder is NSTextView), editingTabID == nil,
            editingFolderID == nil
        else { return false }
        if event.keyCode == 53 {
            clearSidebarSelection()
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                selectedSidebarItems = Set(sidebarSelectionUnits.flatMap { $0 })
                return true
            case "c":
                copySelectedLinks()
                return true
            case "d":
                if selectedFolders.isEmpty { duplicateTabs(selectedActionTabIDs) }
                return true
            case "w":
                requestDeleteTabs(
                    selectedActionTabIDs.filter { id in
                        activeSpace.tabs.contains { $0.id == id && $0.placement == .current }
                    })
                return true
            default: break
            }
        }
        if event.keyCode == 51 {
            deleteSidebarSelection()
            return true
        }
        if event.keyCode == 36, let id = selectionFocusedID {
            if activeSpace.folders.contains(where: { $0.id == id }) {
                updateFolder(id) { $0.isExpanded.toggle() }
            } else {
                selectTab(id)
            }
            return true
        }
        let units = sidebarSelectionUnits
        if [123, 124, 125, 126, 115, 119].contains(event.keyCode), !units.isEmpty {
            let current = units.firstIndex { $0.contains(selectionFocusedID ?? selectedTab?.id ?? UUID()) } ?? 0
            let backwards = [123, 126, 115].contains(event.keyCode)
            let edge = modifiers.contains(.command) || [115, 119].contains(event.keyCode)
            let index =
                edge ? (backwards ? 0 : units.count - 1) : min(max(current + (backwards ? -1 : 1), 0), units.count - 1)
            let id = units[index][0]
            if modifiers.contains(.shift) {
                clickSidebarItem(id, modifiers: modifiers)
            } else {
                selectedSidebarItems = Set(units[index])
                selectionFocusedID = id
                selectionAnchor = id
                selectionRangeBase = nil
            }
            return true
        }
        return false
    }
    func copySelectedLinks() {
        let links = sidebarOrder.filter { selectedActionTabIDs.contains($0.id) }.compactMap { $0.url?.absoluteString }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }
}
