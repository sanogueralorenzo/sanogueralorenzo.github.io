import AppKit

@MainActor
final class BrowserContentStartup {
    private let owner: BrowserSessionOwner
    private let packages: BrowserContentPackages
    private let download = BrowserContentPackageDownload()
    private let present: (NSWindow?) -> Void
    private var window: BrowserContentStartupWindow?
    private var checkedUpstream = false

    init(owner: BrowserSessionOwner, present: @escaping (NSWindow?) -> Void) {
        self.owner = owner
        packages = BrowserContentPackages(profile: owner.persistence.directory)
        self.present = present
    }

    func prepare() async -> Bool {
        do {
            let available = await packages.available()
            let candidate: BrowserContentPackage
            if let pending = available.pending {
                candidate = pending
            } else if let active = available.active {
                owner.contentExtension.select(active)
                return true
            } else {
                show(.downloading)
                checkedUpstream = true
                let release = try await download.latest()
                candidate = try await stage(release)
            }
            do {
                try await activate(candidate)
            } catch {
                try Task.checkCancellation()
                try await packages.discard()
                throw error
            }
            return true
        } catch {
            if !Task.isCancelled {
                NSLog("Content blocking could not be prepared: %@", error.localizedDescription)
                show(.failed)
            }
            return false
        }
    }

    func checkForUpdate() async {
        guard !checkedUpstream, let active = owner.contentExtension.package?.manifest else { return }
        checkedUpstream = true
        do {
            let release = try await download.latest()
            guard release.sha256 != active.upstreamSHA256,
                release.version.compare(active.version, options: .numeric) != .orderedAscending
            else { return }
            _ = try await stage(release)
        } catch {
            if !Task.isCancelled { NSLog("Content blocking update could not be downloaded: %@", error.localizedDescription) }
        }
    }

    func showWindow() { present(window?.window) }

    private func stage(_ release: BrowserContentRelease) async throws -> BrowserContentPackage {
        let data = try await download.fetch(release)
        try Task.checkCancellation()
        return try await packages.stage(release, data: data)
    }

    private func activate(_ package: BrowserContentPackage) async throws {
        show(.preparing)
        owner.contentExtension.select(package)
        _ = try await owner.contentExtension.load(.full)
        let enabled = owner.session.spaces.filter { $0.browsingPreferences?.blocksContent ?? owner.session.preferences.blocksContent }
        let space = enabled.first { $0.id == owner.session.selectedSpaceID } ?? enabled.first
        let blocker = space.map { owner.contentBlocker(for: $0.id) }
        do {
            if blocker != nil { _ = await owner.contentExtension.prepareDefaultRules(for: owner) }
            try await blocker?.setEnabled(true)
            try Task.checkCancellation()
            try await packages.activate(package)
            close()
        } catch {
            if let blocker, let space {
                await blocker.cancelPreparation()
                owner.contentBlockers[space.id] = nil
            }
            throw error
        }
    }

    private func show(_ phase: BrowserContentStartupWindow.Phase) {
        if window == nil { window = BrowserContentStartupWindow(phase: phase) }
        window?.state.phase = phase
        showWindow()
    }

    private func close() {
        window?.window?.orderOut(nil)
        window = nil
    }
}
