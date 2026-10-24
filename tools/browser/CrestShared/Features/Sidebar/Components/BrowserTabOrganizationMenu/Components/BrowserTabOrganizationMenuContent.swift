import SwiftUI

struct BrowserTabOrganizationMenuContent: View {
    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    var isLoaded = true
    var renameTab: (() -> Void)? = nil
    var changeIcon: (() -> Void)? = nil

    @Environment(\.layoutDirection) private var layoutDirection

    init(menu: BrowserTabOrganizationMenu) {
        tab = menu.tab
        context = menu.context
        assignment = menu.assignment
        isLoaded = menu.isLoaded
        renameTab = menu.renameTab
        changeIcon = menu.changeIcon
    }

    private var browser: BrowserStore { context.browser }
    private var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }

    var body: some View {
        if context.takesPartInTabSharing(tab.id) {
            Button {
                performIfCurrent { context.stopTabSharing(tab.id) }
            } label: {
                Label {
                    Text("Stop Sharing", comment: "Stops the tab sharing a tab takes part in.")
                } icon: {
                    Image(systemName: "rectangle.slash")
                }
            }

            Divider()
        }

        if tab.isWebPage {
            Button("Copy Link URL", systemImage: "link") {
                organizationAction.copyLinkURL(for: assignment)
            }
            .disabled(!context.isCurrent(sourceAssignment))

            Divider()
        }

        if let renameTab {
            Button("Rename Tab…", systemImage: "pencil") {
                performIfCurrent { renameTab() }
            }

            Divider()
        }

        if !tab.isStartPage {
            BrowserTabEditActions(
                tab: tab,
                favicons: context.favicons,
                isLoaded: isLoaded,
                pullNewIcon: { context.pullNewIcon(tab.id) },
                restoreSavedLocation: context.restoreSavedLocation.map { restore in { restore(tab.id) } },
                performIfCurrent: performIfCurrent,
                replaceSavedLocation: {
                    browser.replaceTabSavedLocationWithCurrent(
                        tab.id,
                        in: assignment.spaceID
                    )
                },
                clearIcon: {
                    browser.clearTabIcon(
                        for: tab.id,
                        matching: sourceAssignment
                    )
                },
                changeIcon: { changeIcon?() }
            )

            Divider()
        }

        // Unpin Tab takes Pin Tab's place so the two read as a pair; it moves
        // the tab to Current Tabs, as ⌘D's Pin or Unpin Tab does.
        if tab.placement == .pinned {
            Button("Unpin Tab", systemImage: "pin.slash") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .current
                    )
                }
            }
        } else {
            Button("Pin Tab", systemImage: "pin") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .pinned
                    )
                }
            }
        }

        if !tab.placement.isDurable, !tab.isStartPage {
            Menu("Add to Current Tabs Folder", systemImage: "folder.badge.plus") {
                Group {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        performIfCurrent {
                            browser.createTabFolder([tab.id], in: assignment.spaceID)
                        }
                    }
                    let folders = context.space.folderChoices(in: [.current]).map(\.folder)
                    if !folders.isEmpty { Divider() }
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            performIfCurrent {
                                browser.fileTabs(
                                    [tab.id], matching: sourceAssignment, into: folder.id, location: .current)
                            }
                        } label: {
                            Label {
                                Text(verbatim: folder.shownTitle)
                            } icon: {
                                BrowserFolderMenuIcon(systemName: "folder.fill", color: folder.displayColor)
                            }
                        }
                        .disabled(folder.id == tab.folderID)
                    }
                }
                .crestMenuActionLabelStyle()
            }
            if tab.folderID != nil {
                Button("Remove from Folder", systemImage: "folder.badge.minus") {
                    performIfCurrent {
                        browser.fileTabs([tab.id], matching: sourceAssignment, into: nil, location: .current)
                    }
                }
            }
        }

        Menu("Save in Folder", systemImage: "folder") {
            Group {
                Button("Saved Tabs", systemImage: "bookmark") {
                    performIfCurrent {
                        browser.moveTab(
                            tab.id,
                            matching: sourceAssignment,
                            to: .saved
                        )
                    }
                }
                .disabled(tab.placement == .saved && tab.folderID == nil)

                let savedFolders = context.space.folderChoices(in: [.saved])
                if !savedFolders.isEmpty {
                    Divider()
                    ForEach(savedFolders) { choice in
                        Button {
                            performIfCurrent {
                                browser.moveTab(
                                    tab.id,
                                    matching: sourceAssignment,
                                    to: .saved,
                                    folderID: choice.id
                                )
                            }
                        } label: {
                            Label {
                                Text(choice.pathTitle)
                            } icon: {
                                BrowserFolderArtwork(
                                    symbol: choice.folder.displaySymbol, color: choice.folder.displayColor)
                            }
                        }
                        .disabled(
                            tab.placement == .saved && tab.folderID == choice.id
                        )
                    }
                }
            }
            .crestMenuActionLabelStyle()
        }

        if tab.placement.isDurable, tab.placement != .pinned {
            Button("Move to Current Tabs", systemImage: "rectangle.stack") {
                performIfCurrent {
                    browser.moveTab(
                        tab.id,
                        matching: sourceAssignment,
                        to: .current
                    )
                }
            }
        }

        let otherSpaces = availableDestinationSpaces
        if !otherSpaces.isEmpty {
            Menu("Move to Space", systemImage: "square.grid.2x2") {
                ForEach(otherSpaces) { space in
                    Button {
                        performIfCurrent {
                            let destinationAssignment =
                                BrowserSpaceRuntimeAssignment(space: space)
                            guard
                                browser.unlockedSpace(matching: destinationAssignment, accessController: spaceAccess)
                                    != nil
                            else { return }
                            browser.moveTab(
                                tab.id,
                                matching: sourceAssignment,
                                into: destinationAssignment
                            )
                        }
                    } label: {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                    .disabled(
                        !browser.canMoveTab(
                            assignment.tabID,
                            matching: sourceAssignment,
                            into: BrowserSpaceRuntimeAssignment(space: space)
                        )
                    )
                }
                .crestMenuActionLabelStyle()
            }
            .tint(.primary)
        }

        Divider()

        Button("Split with Current Tab", systemImage: "rectangle.split.2x1") {
            performIfCurrent {
                browser.splitTabWithSelectedTab(
                    tab.id,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(
            !browser.canSplitTabWithSelectedTab(
                assignment.tabID,
                matching: sourceAssignment
            )
        )

        if isRenderableSplitMember {
            moveButton(.left, title: "Move Left", systemImage: "arrow.left")
            moveButton(.right, title: "Move Right", systemImage: "arrow.right")

            Button("Remove from Split", systemImage: "rectangle.badge.minus") {
                performIfCurrent {
                    browser.removeTabFromSplit(
                        tab.id,
                        matching: sourceAssignment
                    )
                }
            }
        }

        Divider()

        if tab.nativeContent == nil {
            Button(
                tab.keepsPageLoaded ? "Stop Keeping Loaded" : "Keep Loaded",
                systemImage: tab.keepsPageLoaded ? "lock.open" : "lock"
            ) {
                performIfCurrent {
                    browser.setTabKeepsPageLoaded(
                        !tab.keepsPageLoaded,
                        for: tab.id,
                        matching: sourceAssignment
                    )
                }
            }

        }

        if isLoaded, tab.nativeContent == nil || tab.placement.isDurable {
            Button(
                !tab.placement.isDurable ? "Unload Tab" : "Close Tab",
                systemImage: !tab.placement.isDurable ? "minus" : "xmark"
            ) {
                performIfCurrent {
                    context.unload(tab.id)
                }
            }
        }

        Button("Duplicate Tab", systemImage: "plus.square.on.square") {
            performIfCurrent {
                browser.duplicateTab(
                    tab.id,
                    matching: sourceAssignment
                )
            }
        }

        Button(
            !tab.placement.isDurable ? "Close Tab" : "Delete Tab",
            systemImage: !tab.placement.isDurable ? "xmark" : "trash",
            role: .destructive
        ) {
            let placement = tab.placement
            performIfCurrent {
                if !placement.isDurable {
                    organizationAction.close(assignment, expectedPlacement: placement)
                } else {
                    organizationAction.delete(assignment, expectedPlacement: placement)
                }
            }
        }
    }

    /// One "Move Left"/"Move Right" item, dimmed once the card is at that end.
    ///
    /// The card at the end of the run keeps the item rather than losing it: a
    /// pair of reordering items that appear and disappear as the card travels
    /// would make the menu jump under the pointer. "Remove from Split" is
    /// absent-or-present because it answers a different question — whether this
    /// row is in a split at all.
    private func moveButton(
        _ direction: BrowserSplitCardMoveDirection,
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        let offset = direction.memberOffset(layoutDirection: layoutDirection)
        return Button(title, systemImage: systemImage) {
            performIfCurrent {
                browser.moveSplitMember(
                    tab.id,
                    by: offset,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(!canStepSplitMember(by: offset))
    }

    private var sourceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    /// Whether this tab sits in a split the sidebar actually draws as a group.
    ///
    /// Membership alone is not enough: a run shorter than the renderable
    /// minimum keeps its group ID in storage so a staggered sync can
    /// reconstitute the split, but presents as a plain tab. Offering to leave a
    /// group nobody can see would be an action with no visible subject, so the
    /// item is absent rather than dimmed — every other tab in the list is a
    /// tab this menu can act on the same way.
    private var isRenderableSplitMember: Bool {
        context.space.shownSplit(containing: tab.id) != nil
    }

    /// Whether the card has another card `offset` places along its split.
    private func canStepSplitMember(by offset: Int) -> Bool {
        guard offset != 0, context.isCurrent(sourceAssignment),
            let groupID = context.space.shownSplit(containing: tab.id)
        else { return false }
        let members = context.space.splitMembers(of: groupID)
        guard let index = members.firstIndex(where: { $0.id == tab.id }) else { return false }
        return members.indices.contains(index + offset)
    }

    private var availableDestinationSpaces: [SpaceModel] {
        browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: spaceAccess)
    }

    /// Runs a menu action only while the window shows the tab's Space,
    /// unlocked, with the profile the menu was built for, and the Space still
    /// holds the tab.
    private func performIfCurrent(_ action: () -> Void) {
        guard context.isCurrent(sourceAssignment), context.space.tabs.contains(tab.id) else { return }
        action()
    }

    private var organizationAction: BrowserTabOrganizationAction {
        BrowserTabOrganizationAction(
            browser: browser,
            spaceAccess: spaceAccess
        )
    }
}
