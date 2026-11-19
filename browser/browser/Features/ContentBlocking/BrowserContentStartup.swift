import AppKit

@MainActor
final class BrowserContentStartup {
    private let owner: BrowserSessionOwner
    private let packages: BrowserContentPackages
    private let download = BrowserContentPackageDownload()
    private let present: (NSWindow?) -> Void
    private var window: BrowserContentStartupWindow?
    private var checkedFeed = false

    init(owner: BrowserSessionOwner, present: @escaping (NSWindow?) -> Void) {
        self.owner = owner
        packages = BrowserContentPackages(profile: owner.persistence.directory)
        self.present = present
    }

    func prepare() async -> Bool {
        do {
            let available = await packages.available()
            if let pending = available.pending {
                do {
                    try await activate(pending)
                    return true
                } catch {
                    try Task.checkCancellation()
                    try? await packages.reject(pending, retaining: available.active)
                    if available.active == nil { throw error }
                    NSLog("Content blocking update could not be applied: %@", error.localizedDescription)
                }
            }
            if let active = available.active {
                owner.contentExtension.select(active)
                close()
                return true
            }
            show(.downloading(nil))
            checkedFeed = true
            let manifest = try await download.latest()
            let package = try await stage(manifest) { [weak self] progress in
                self?.window?.setDownloadProgress(progress)
            }
            do {
                try await activate(package)
            } catch {
                try Task.checkCancellation()
                try? await packages.reject(package, retaining: nil)
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
        guard !checkedFeed, let active = owner.contentExtension.package else { return }
        checkedFeed = true
        do {
            let manifest = try await download.latest()
            guard await packages.shouldDownload(manifest, after: active) else { return }
            _ = try await stage(manifest)
        } catch {
            if !Task.isCancelled { NSLog("Content blocking update could not be downloaded: %@", error.localizedDescription) }
        }
    }

    func showWindow() { present(window?.window) }

    private func stage(
        _ manifest: BrowserContentPackage.Manifest, progress: BrowserContentPackageDownload.Progress? = nil
    ) async throws -> BrowserContentPackage {
        let data = try await download.fetch(progress: progress)
        try Task.checkCancellation()
        return try await packages.stage(manifest, data: data)
    }

    private func activate(_ package: BrowserContentPackage) async throws {
        show(.preparing)
        owner.contentExtension.select(package)
        _ = try await owner.contentExtension.load(.full)
        let enabled = owner.session.spaces.filter { $0.browsingPreferences?.blocksContent ?? owner.session.preferences.blocksContent }
        let space = enabled.first { $0.id == owner.session.selectedSpaceID } ?? enabled.first
        let blocker = space.map { owner.contentBlocker(for: $0.id) }
        do {
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
