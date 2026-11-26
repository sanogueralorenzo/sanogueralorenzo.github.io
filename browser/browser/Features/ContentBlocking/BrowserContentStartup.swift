import Foundation

@MainActor
final class BrowserContentStartup {
    enum Phase {
        case downloading
        case preparing
        case failed
    }

    private let owner: BrowserSessionOwner
    private let packages: BrowserContentPackages
    private let download = BrowserContentPackageDownload()
    private var checkedUpstream = false

    init(owner: BrowserSessionOwner) {
        self.owner = owner
        packages = BrowserContentPackages(profile: owner.persistence.directory)
    }

    func prepare(report: (Phase) -> Void) async -> Bool {
        do {
            let available = await packages.available()
            let candidate: BrowserContentPackage
            if let pending = available.pending {
                candidate = pending
            } else if let active = available.active {
                owner.contentExtension.select(active)
                return true
            } else {
                report(.downloading)
                checkedUpstream = true
                let release = try await download.latest()
                candidate = try await stage(release)
            }
            report(.preparing)
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
                report(.failed)
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

    private func stage(_ release: BrowserContentRelease) async throws -> BrowserContentPackage {
        let data = try await download.fetch(release)
        try Task.checkCancellation()
        return try await packages.stage(release, data: data)
    }

    private func activate(_ package: BrowserContentPackage) async throws {
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
        } catch {
            if let blocker, let space {
                await blocker.cancelPreparation()
                owner.contentBlockers[space.id] = nil
            }
            throw error
        }
    }
}
