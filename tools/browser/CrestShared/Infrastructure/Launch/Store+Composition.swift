import CryptoKit
import Foundation

extension BrowserStore {
    /// The store of this launch's session. A launch that needs isolation keeps
    /// its own directory or a fixture in memory. Otherwise the core's file
    /// holds the session, carried once from the release before it.
    static func production(core: CrestCore, launchEnvironment: BrowserLaunchEnvironment = .current) throws
        -> BrowserStore
    {
        // Keep the persistence boundary safe even if a future composition root
        // accidentally calls `production` for a fixture or preview launch.
        // Sample Spaces must never replace the installed session or be staged as
        // Cloud tombstones for the user's real Space IDs.
        if launchEnvironment.requiresIsolation {
            return try isolatedLaunch(core: core, launchEnvironment: launchEnvironment)
        }
        let favicons: any BrowserFaviconStoring = BrowserFaviconFileStore.production() ?? InMemoryBrowserFaviconStore()
        let stored = try migratedStorage(core: core, legacy: .installed, favicons: favicons, seed: nil)
        return production(
            stored: stored, core: core, favicons: favicons, credentialVault: KeychainCredentialVault())
    }

    /// The store over the session the core keeps in its file, which `stored`
    /// opened. The core staged the session when it opened and saves every
    /// journal it accepts with the session; the cloud transport reaches that
    /// journal through the core alone.
    static func production(
        stored: BrowserCoreSessionAuthority, core: CrestCore, favicons: any BrowserFaviconStoring,
        credentialVault: any CredentialVault
    ) -> BrowserStore {
        BrowserStore(
            credentialVault: credentialVault,
            browsingMode: .standard,
            family: BrowserStoreFamily(stored: stored, storage: core, favicons: favicons),
            core: core
        )
    }

    /// Launch cleanup and retention: the core sweeps this family's session
    /// before any scene is on screen, keeping every tab an open window shows
    /// and every tab a saved window's record shows. The core remembers the
    /// sweep, so the first active scene does not repeat it.
    func sweepAtLaunch() {
        sweepExpiredBrowsingData()
    }

    static func preview() -> BrowserStore {
        BrowserStore(seed: .preview)
    }

    static func isolatedLaunch(core: CrestCore, launchEnvironment: BrowserLaunchEnvironment) throws -> BrowserStore {
        if let isolationID = launchEnvironment.persistentIsolationID,
            let store = try persistentIsolatedLaunch(
                core: core, launchEnvironment: launchEnvironment, isolationID: isolationID)
        {
            return store
        }
        return inMemoryIsolatedLaunch(launchEnvironment: launchEnvironment, core: core)
    }

    private static func inMemoryIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        core: CrestCore
    ) -> BrowserStore {
        // The fixture opens as a seed, which the core repairs and never saves
        // or syncs: only the session the core keeps in its file syncs.
        return BrowserStore(
            seed: isolatedFixtureSeed(for: launchEnvironment) ?? .firstInstall,
            credentialVault: InMemoryCredentialVault(), core: core)
    }

    private static func persistentIsolatedLaunch(
        core: CrestCore, launchEnvironment: BrowserLaunchEnvironment, isolationID: String
    ) throws -> BrowserStore? {
        let namespace = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        guard let directory = core.storageDirectory, let defaults = UserDefaults(suiteName: namespace) else {
            return nil
        }
        let favicons = BrowserFaviconFileStore(
            rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
        let stored = try migratedStorage(
            core: core, legacy: BrowserLegacySessionDefaults(defaults: defaults, journalDefaults: []),
            favicons: favicons, seed: isolatedFixtureSeed(for: launchEnvironment))
        return production(
            stored: stored, core: core, favicons: favicons,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace))
    }

    /// Where the core keeps this launch's session file: the installed app's
    /// directory, or the one a persistent review launch keeps apart from it.
    /// Nil keeps the session in memory.
    static func sessionDirectory(for launchEnvironment: BrowserLaunchEnvironment) throws -> URL? {
        let isolationID = launchEnvironment.persistentIsolationID
        guard !launchEnvironment.requiresIsolation || isolationID != nil else { return nil }
        var directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        .appendingPathComponent("ControlPlane", isDirectory: true)
        if launchEnvironment.requiresIsolation, let isolationID {
            let namespace = SHA256.hash(data: Data(isolationID.utf8)).map { String(format: "%02x", $0) }.joined()
            directory = directory.appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
        }
        return directory
    }

    /// The one core this launch creates, keeping its session in
    /// `sessionDirectory(for:)`. A file the core cannot use is a startup
    /// failure the recovery screen answers.
    static func launchCore(for launchEnvironment: BrowserLaunchEnvironment) throws -> CrestCore {
        let directory: URL?
        do { directory = try sessionDirectory(for: launchEnvironment) } catch {
            throw BrowserSessionStartupFailure(storageDirectory: nil, underlying: error)
        }
        do { return try CrestCore(configuration: AppConfiguration(storageDirectory: directory?.path)) } catch {
            throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error)
        }
    }

    /// Opens the session `core` keeps in its file. On the first launch whose
    /// file holds none, the core carries the installed release's defaults
    /// session, history and sync journal into the file, or installs `seed`
    /// when there is nothing it can carry, or without one the session a first
    /// launch starts with; the images the installed session held inside its
    /// tabs land in `favicons`. The legacy values are left in place, so this
    /// is also the seam an upgrade test drives with its own directory,
    /// defaults suite and favicon store.
    static func migratedStorage(
        core: CrestCore, legacy: BrowserLegacySessionDefaults, favicons: any BrowserFaviconStoring,
        seed: SessionState.Seed?
    ) throws -> BrowserCoreSessionAuthority {
        guard let directory = core.storageDirectory else {
            preconditionFailure("A core that keeps nothing on disk has no stored session to open.")
        }
        do {
            let stored: BrowserCoreSessionAuthority
            if let opened = try openStored(core: core, favicons: favicons) {
                stored = opened
            } else {
                let adoption = AdoptLegacySession(installed: legacy.values, seed: seed)
                for case .sessionAdopted(let adopted) in try core.send(adoption) {
                    for favicon in adopted.favicons {
                        favicons.reconcile(favicon.image, tabID: favicon.tabID)
                    }
                }
                stored = try BrowserCoreSessionAuthority.openStored(in: core, favicons: favicons)
            }
            return stored
        } catch {
            throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error)
        }
    }

    /// The session `core` keeps in its file, opened, or nil while the file
    /// holds none yet.
    private static func openStored(core: CrestCore, favicons: any BrowserFaviconStoring) throws(Rejection)
        -> BrowserCoreSessionAuthority?
    {
        do {
            return try BrowserCoreSessionAuthority.openStored(in: core, favicons: favicons)
        } catch {
            guard case .noStoredSession = error else { throw error }
            return nil
        }
    }

    /// The session an isolated launch starts from, or nil for the one a first
    /// launch starts with, which an isolated run of cloud sync or onboarding
    /// takes.
    private static func isolatedFixtureSeed(for launchEnvironment: BrowserLaunchEnvironment) -> SessionState.Seed? {
        if launchEnvironment.requestsIsolatedCloudSync
            || launchEnvironment.forcesOnboardingWelcome
            || launchEnvironment.forcesMacOnboardingSetup
            || launchEnvironment.forcesMobileOnboardingSetup
        {
            return nil
        }
        #if CREST_PERFORMANCE_HARNESS
            if let performanceSeed = BrowserPerformanceSoakFixture.makeSeed(
                baseURLString: launchEnvironment.performanceBaseURLString,
                rawTabCount: launchEnvironment.performanceTabCount,
                isHeavy: launchEnvironment.performanceHeavySession,
                runID: launchEnvironment.performanceRunID
            ) {
                return performanceSeed
            }
        #endif
        return launchEnvironment.presentsShowcaseSession ? .showcase : .preview
    }

    /// A window over a new private workspace, which starts from the core's
    /// private template and keeps nothing.
    static func privateBrowsing(core: CrestCore = CrestCore()) -> BrowserStore {
        BrowserStore(
            credentialVault: PrivateBrowsingCredentialVault(),
            browsingMode: .privateBrowsing,
            family: BrowserStoreFamily(privateIn: core),
            core: core
        )
    }
}
