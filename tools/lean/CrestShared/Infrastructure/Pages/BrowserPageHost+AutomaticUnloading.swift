import Foundation

extension BrowserPageHost {
    // MARK: - Actions - Automatic unloading

    /// One loop per shared workspace host, including private and review hosts.
    /// The core owns eligibility; the engine checks unsaved work without UI.
    func startAutomaticUnloading(core: CrestCore) {
        guard automaticUnloadTask == nil else { return }
        automaticUnloadTask = Task { @MainActor [weak self, weak core] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let core else { return }
                await self?.unloadIdlePages(core: core)
            }
        }
    }

    func unloadIdlePages(core: CrestCore) async {
        guard let candidates = try? core.query(IdlePages()).pages else { return }
        for candidate in candidates {
            guard !Task.isCancelled,
                let page = residentPages.first(where: { $0.corePage.id == candidate.pageID }),
                await page.pageEngine.canAutomaticallyUnload(), !Task.isCancelled,
                residentPages.contains(where: { $0 === page })
            else { continue }
            // Keep the platform's disk archive as well as the core's in-memory
            // restore state. Neither path changes tab identity or placement.
            if let tabID = page.corePage.state?.tabID { archiveTabState(for: tabID) }
            _ = try? core.send(
                UnloadIdlePage(
                    pageID: candidate.pageID, documents: candidate.documents, hiddenSince: candidate.hiddenSince))
        }
    }
}
