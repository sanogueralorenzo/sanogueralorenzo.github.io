namespace CrestCore.Contracts;

/// What an intent changed. A change carries the resulting values, never an
/// instruction the caller has to work out again.
public abstract record Change {
    #region Actions - Sync

    /// The names of the sync records this change removed from `previous`,
    /// the session it replaced. A change that removes no Space, folder, tab,
    /// archived tab or history entry removes none.
    internal virtual IEnumerable<string> RemovedRecords(SessionState previous) => [];

    #endregion
}

/// The rule that refused an intent or a query.
public abstract record Rejection;

/// Settings the host hands the core once: when it creates it, or when an
/// engine binding registers. A configuration is not a message: it has no wire
/// tag and is read only where it is expected.
public abstract record Configuration;

/// How the host creates the core. `StorageDirectory` is where the core keeps
/// `session.sqlite`; null keeps everything in memory, as private browsing,
/// temporary workspaces, tests and previews need. `Platform` is the device
/// class the core answers for, whose defaults its rules apply, such as each
/// shortcut's default keys. `ImportNames` holds the names an import gives the
/// Spaces it names itself, in the person's language; a source missing there
/// names them in English.
public sealed record AppConfiguration(string? StorageDirectory, DevicePlatform Platform,
    IReadOnlyList<ImportSpaceNames>? ImportNames = null) : Configuration;
