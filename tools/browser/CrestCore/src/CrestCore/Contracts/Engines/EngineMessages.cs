namespace CrestCore.Contracts;

#region Changes

/// An engine registered or went away. `Roster` holds every engine registered
/// now.
public sealed record EnginesChanged(EngineRoster Roster) : Change;

#endregion

#region Rejections

/// Another engine, `Current`, is already the one new pages open on.
public sealed record DefaultEngineAlreadyRegistered(EngineKind Current) : Rejection;

/// A binding for this engine is already registered.
public sealed record EngineAlreadyRegistered(EngineKind Kind) : Rejection;

/// The engine does not support `Capability`, which every engine must support
/// to register.
public sealed record EngineLacksCapability(EngineKind Kind, EngineCapability Capability) : Rejection;

/// No registered engine can host a new page: none is the default.
public sealed record EngineNotRegistered : Rejection;

#endregion

#region Configurations

/// What an engine binding tells the core once, when it registers: which engine
/// it is, the capabilities it supports, and whether new pages open on it. It
/// must support every required capability, one engine is the default, and each
/// kind registers once.
public sealed record EngineRegistration(EngineKind Kind, IReadOnlyList<EngineCapability> Capabilities, bool IsDefault)
    : Configuration;

#endregion

#region Models

/// Why the engine warns about a download, or blocked it.
public enum EngineDownloadWarning {
    /// It came over a connection someone else could have changed.
    InsecureConnection,

    /// Its type of file can change the computer.
    DangerousFile,

    /// It is not commonly downloaded, so the engine could not confirm it is safe.
    UncommonContent,

    /// It may change the browser's or the computer's settings.
    PotentiallyUnwanted,

    /// The engine blocked it for its insecure connection.
    InsecureBlocked,

    /// The engine blocked it for its safety or organization policy verdict.
    PolicyBlocked
}

/// One engine this device registered, as the read model shows it: the
/// capabilities its binding supports, in `EngineCapability.All` order, and
/// whether new pages open on it. A page's own engine answers what the page
/// can do.
public sealed record EngineState(EngineKind Kind, IReadOnlyList<EngineCapability> Capabilities, bool IsDefault);

/// What an engine needs to bring a page back as it was: its history, opaque to
/// the core, at `Url`, the address it showed. The core keeps it in memory
/// only, never in a saved or synced file.
public sealed record PageRestoreState(string Url, byte[] State);

/// One entry of a page's back and forward history: the identity its engine
/// gave it when it committed, which the entry keeps however the page moves
/// through its history, its address and the title it had.
public sealed record PageHistoryEntry(Guid Id, string Url, string Title);

#endregion
