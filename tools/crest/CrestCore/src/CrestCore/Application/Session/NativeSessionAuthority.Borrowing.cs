using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private readonly NativeSessionAuthority? borrowedSource;
    private readonly Guid borrowedSpace, borrowedProfile;
    private bool released;

    /// The session takes no edits: its workspace closed.
    internal bool IsReleased {
        get {
            lock (Gate) return released;
        }
    }

    #endregion

    #region Constructors

    private NativeSessionAuthority(SessionState initial, NativeSessionAuthority source, Guid space, Guid profile) {
        session = initial; workspaceKind = WorkspaceKind.Borrowed;
        privateBrowsing = source.privateBrowsing; access = source.access;
        borrowedSource = source; borrowedSpace = space; borrowedProfile = profile;
        Index(session);
    }

    #endregion

    #region Actions - Borrowing

    /// A memory-only session that shows the Space `spaceId` names, with its
    /// settings and profile and none of its records, and consults this
    /// session's grants. Throws `Rejected` naming the rule that refuses it; see
    /// `BorrowSpace`.
    internal NativeSessionAuthority Borrow(Guid spaceId, Guid profileId) {
        lock (Gate) {
            if (released) throw new Rejected(new UnknownWorkspace(workspaceId));
            if (!workspaceKind.OwnsSpaces) throw new Rejected(new BorrowedProfileRequiresOwner(workspaceId));
            var original = session.KnownSpace(spaceId);
            if (session.PendingDeletion(spaceId) is not null) throw new Rejected(new SpaceBeingDeleted(spaceId));
            if (original.ProfileId != profileId) throw new Rejected(new SpaceProfileChanged(spaceId));
            if (IsLockedUnderGate(original)) throw new Rejected(new SpaceLocked(spaceId));
            var borrowed = original with { Folders = [], Tabs = [], SplitGroups = [], ArchivedTabs = [], History = [] };
            return new(new([borrowed], original.Id, null, [], null), this, spaceId, profileId);
        }
    }

    /// Whether this session borrows its Space from `owner`.
    internal bool Borrows(NativeSessionAuthority owner) => ReferenceEquals(borrowedSource, owner);

    /// Whether the workspace this session borrows from no longer lends its
    /// Space: it closed, or the Space is gone, uses another profile or is being
    /// deleted. A session that borrows nothing never loses its source.
    internal bool LostSource() {
        lock (Gate) return borrowedSource is { } source && Lent(source) is null;
    }

    /// Brings the borrowed Space's settings up to date with its owner, keeping
    /// its own records and saved-tabs expansion, and answers the state it
    /// replaced and the new one; null when they already match, the source no
    /// longer lends the Space, or a reservation holds the session. The new
    /// state is never saved or staged, since a borrowed session keeps nothing.
    internal (SessionState Previous, SessionState Next)? FollowOwner() {
        lock (Gate) {
            if (released || replacement is not null || borrowedSource is not { } source || Lent(source) is not { } original)
                return null;
            var local = session.Spaces.Single();
            var refreshed = BorrowedSpace(original, local);
            if (refreshed == local) return null;
            var next = session with { Spaces = [refreshed] };
            return (Accept(next), next);
        }
    }

    /// The Space `source` lends this session, as it holds it now, or null when
    /// it closed, holds no such Space, holds it with another profile or is
    /// deleting it. The caller holds the gate.
    private SpaceState? Lent(NativeSessionAuthority source) {
        var original = source.session.Space(borrowedSpace);
        return source.released || original is null || original.ProfileId != borrowedProfile
            || source.session.PendingDeletion(borrowedSpace) is not null ? null : original;
    }


    /// The borrowed Space with its owner's current settings and its own
    /// organization. Organization belongs to the temporary workspace: its
    /// records, its split metadata and whether its saved tabs are expanded.
    /// Every other setting follows its owner.
    private static SpaceState BorrowedSpace(SpaceState original, SpaceState local) => original with {
        Folders = local.Folders,
        Tabs = local.Tabs,
        SplitGroups = local.SplitGroups,
        ArchivedTabs = local.ArchivedTabs,
        History = local.History,
        Settings = original.Settings with {
            IsSavedTabsExpanded = local.Settings.IsSavedTabsExpanded,
            SavedTabsExpansionModifiedAt = local.Settings.SavedTabsExpansionModifiedAt
        }
    };

    /// Refuses `value`, a state of a borrowed session, unless it shows only
    /// its Space with the settings its owner holds now: `UnknownSpace` once
    /// the owner no longer lends the Space, `SpaceBeingDeleted` while the
    /// owner deletes it, and `BorrowedProfileRequiresOwner` for a change only
    /// the owner may make. A temporary workspace borrows one existing profile;
    /// it never replaces it. Any other session always passes.
    private void ValidateBorrowedSession(SessionState value) {
        if (borrowedSource is not { } source) return;
        if (source.released || source.session.Space(borrowedSpace) is not { } original
            || original.ProfileId != borrowedProfile) throw new Rejected(new UnknownSpace(borrowedSpace));
        if (source.session.PendingDeletion(borrowedSpace) is not null) throw new Rejected(new SpaceBeingDeleted(borrowedSpace));
        if (!ShowsCurrent(original, value)) throw new Rejected(new BorrowedProfileRequiresOwner(workspaceId));
    }

    /// Whether `value`, a state of a borrowed session, shows only its Space
    /// with the settings `original`, the Space its owner lends, holds now.
    private static bool ShowsCurrent(SpaceState original, SessionState value) =>
        value.Spaces.Count == 1 && BorrowedSpace(original, value.Spaces[0]) == value.Spaces[0];

    /// Whether the session takes an edit it did not ask for, such as a page's
    /// report or a window showing a tab: its workspace is open, no
    /// reservation holds it, and a borrowed session's owner still lends its
    /// Space with the settings it shows; the core brings a borrowed session
    /// up to date as soon as its owner changes. The caller holds the gate.
    private bool TakesEdits() => !released && replacement is null
        && (borrowedSource is not { } source || Lent(source) is { } original && ShowsCurrent(original, session));

    /// Takes no more edits. The core then drops the workspace's pages and
    /// windows and publishes that it closed.
    internal void Close() {
        lock (Gate) released = true;
    }

    #endregion
}
