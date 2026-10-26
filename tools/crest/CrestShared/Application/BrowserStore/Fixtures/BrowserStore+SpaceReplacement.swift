#if DEBUG
    import Foundation

    extension BrowserStore {
        /// Deletes the Space `spaceID` whole, as the app does once every engine
        /// erased its profile's data, for tests of what an assignment captured
        /// before it may still do.
        func removeSpaceForTesting(_ spaceID: UUID) {
            let operation = UUID()
            let window = windowID
            guard let profileID = spaceModel(spaceID)?.profileID else {
                preconditionFailure("A test removed a Space the session does not hold.")
            }
            do {
                try family.commit(
                    BeginDeletingSpace(
                        workspaceID: family.workspaceID, windowID: window, spaceID: spaceID,
                        operationID: operation), from: self)
                eraseProfileForTesting(profileID)
                try family.commit(
                    FinishDeletingSpace(
                        workspaceID: family.workspaceID, windowID: window, spaceID: spaceID,
                        operationID: operation), from: self)
            } catch {
                preconditionFailure("The core refused to remove a Space for a test: \(error)")
            }
        }

        /// Has every engine erase `profileID`, which keeps nothing on disk in a
        /// test, so each answers at once: the core lets a Space go only once
        /// they all have.
        private func eraseProfileForTesting(_ profileID: UUID) {
            let requestID = UUID()
            let sent: [Change]
            do {
                sent = try core.send(DeleteProfileData(requestID: requestID, profileID: profileID, ephemeral: true))
            } catch {
                preconditionFailure("The core refused to erase a profile for a test: \(error)")
            }
            // What the engines answered arrives through the core's next drain.
            let erased = (sent + core.drain()).contains { change in
                guard case .dataDeleted(let deleted) = change else { return false }
                return deleted.requestID == requestID && deleted.deleted
            }
            guard erased else { preconditionFailure("The engines did not erase a profile for a test.") }
        }

        /// Gives the Space `spaceID` the profile `profileID`, as only a cloud
        /// replacement can: the Space goes, then comes back whole under the new
        /// profile, in its place in the order, and this window shows what it
        /// showed. For tests of what an assignment captured before the
        /// replacement may still do. The workspace takes imports, so it is a
        /// persistent one.
        func replaceProfileForTesting(of spaceID: UUID, with profileID: UUID = UUID()) {
            guard let space = spaceModel(spaceID)?.value else {
                preconditionFailure("A test replaced the profile of a Space the session does not hold.")
            }
            let order = spaceModels.map(\.id)
            let shownSpace = selectedSpaceID
            let shownTab = selectedTabID(in: spaceID)
            let seed = space.seed
            let replacement = SpaceState.Seed(
                id: seed.id, profileID: profileID, settings: seed.settings, folders: seed.folders, tabs: seed.tabs,
                splitGroups: seed.splitGroups, archivedTabs: seed.archivedTabs, history: seed.history)
            // A Space is never the last one while it goes.
            let placeholder = UUID()
            if spaceModels.count == 1 {
                _ = family.send(
                    CreateSpace(
                        workspaceID: family.workspaceID, windowID: windowID, spaceID: placeholder),
                    from: self)
            }
            // The tabs it brings back wear the images they wore.
            var images: [UUID: Data] = [:]
            for tabID in space.tabs.map(\.id) + space.archivedTabs.map(\.tab.id) {
                images[tabID] = core.state.favicons.image(of: tabID)
            }
            removeSpaceForTesting(spaceID)
            core.state.favicons.offer(FaviconAssets.Offer(imported: [images]), in: family.workspaceID)
            defer { core.state.favicons.withdrawOffer(in: family.workspaceID) }
            do {
                try family.commit(
                    ImportSpaces(workspaceID: family.workspaceID, windowID: windowID, spaces: [replacement]), from: self
                )
            } catch {
                preconditionFailure("The core refused to bring a Space back for a test: \(error)")
            }
            if spaceModel(placeholder) != nil { removeSpaceForTesting(placeholder) }
            family.send(ReorderSpaces(workspaceID: family.workspaceID, spaceIDs: order), from: self)
            selectPresentedSpace(shownSpace)
            if let shownTab { activateSessionTab(shownTab, in: spaceID) }
        }
    }
#endif
