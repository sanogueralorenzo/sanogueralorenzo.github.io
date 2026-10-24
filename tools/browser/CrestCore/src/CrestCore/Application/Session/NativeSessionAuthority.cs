using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Owns the native app's durable session as typed records. Intents edit it; only
/// an accepted state becomes visible, and the device publishes what each accepted
/// state changed. Accepted states are immutable, so storage can serialize an older
/// checkpoint on its worker while the UI continues editing the current one. An
/// intent is accepted, or reserved while it is saved, under the lock that computed
/// its edit, so it never overwrites a change it did not see; nothing outside the
/// core names a revision. The session holds browsing data only: which Space and
/// tab a window shows is window state, so selection fields in an older session are
/// dropped here and never written. Intents read what the window shows as context.
public sealed partial class NativeSessionAuthority {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    internal static readonly object Gate = new();
    private SessionState session;
    internal SessionState AcceptedSession => session;
    /// The identities `session` holds, which each edit's state is checked against.
    private readonly SessionIdentities identities = new();
    private NativeSessionReplacement? replacement;
    private readonly WorkspaceKind workspaceKind;
    private readonly bool privateBrowsing;
    /// The file a persistent session the core loaded keeps; null in memory.
    private readonly SessionStorage? storage;
    /// Counts the accepted states, so storage saves them in order and `Saved`
    /// can name the newest on disk.
    internal ulong Revision { get; private set; } = 1;

    /// What kind of workspace this session is.
    internal WorkspaceKind Kind => workspaceKind;

    /// The identities the accepted session holds, which each edit is checked
    /// against. Read it under the gate.
    internal SessionIdentities Identities => identities;

    #endregion

    #region Constructors

    /// A memory-only session of `kind` that starts as `initial` and keeps
    /// nothing: it is never saved or synced.
    internal NativeSessionAuthority(WorkspaceKind kind, SessionState initial) {
        ArgumentNullException.ThrowIfNull(kind);
        ArgumentNullException.ThrowIfNull(initial);
        workspaceKind = kind;
        privateBrowsing = kind.IsPrivate;
        session = initial;
        Index(session);
    }

    /// The persistent session the core loaded from `storage` and repaired.
    /// Every revision it accepts is saved there.
    internal NativeSessionAuthority(SessionState stored, SessionStorage storage) {
        workspaceKind = WorkspaceKind.Persistent;
        session = stored;
        Index(session);
        this.storage = storage;
        storage.Enqueue(session, Revision);
    }

    #endregion

    #region Actions - Session validation

    /// Throws `Rejected` with `InvalidSession` unless `value`, a session that
    /// arrives whole, is one a workspace can hold; see `SessionIdentities`.
    private static void Validate(SessionState value) {
        if (SessionIdentities.Flaw(value) is { } flaw) throw new Rejected(new InvalidSession(flaw));
    }

    /// Throws `Rejected` with `InvalidSession` unless `next`, an edit of
    /// `basis`, is a session a workspace can hold, reading only what the edit
    /// changed when `basis` is the accepted state. The caller holds the gate.
    private void Validate(SessionState basis, SessionState next) {
        if (identities.Flaw(basis, next) is { } flaw) throw new Rejected(new InvalidSession(flaw));
    }

    /// Throws `Rejected` with `InvalidSession` unless `value`, the state a
    /// session opens with, is one a workspace can hold, which each edit is
    /// then checked against.
    private void Index(SessionState value) {
        if (identities.Index(value) is { } flaw) throw new Rejected(new InvalidSession(flaw));
    }

    internal static SessionState Replacing(SessionState session, params SpaceState[] edited) => session with {
        Spaces = [.. session.Spaces.Select(space => edited.FirstOrDefault(value => value.Id == space.Id) ?? space)]
    };

    #endregion

    #region Actions - Session revisions

    /// Makes `next` the accepted state, saved behind as a new revision, and
    /// answers the state it replaced. The caller holds the gate.
    private SessionState Accept(SessionState next) {
        var previous = session;
        session = next;
        Revision = checked(Revision + 1);
        storage?.Enqueue(session, Revision);
        identities.Accepted(previous, next);
        return previous;
    }

    /// The stored parts of the accepted state.
    internal NativeSessionCheckpoint Checkpoint() {
        lock (Gate) return new(session);
    }

    #endregion
}
