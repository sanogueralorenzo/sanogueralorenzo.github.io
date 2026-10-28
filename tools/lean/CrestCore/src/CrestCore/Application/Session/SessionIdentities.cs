using System.Diagnostics;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The identities an accepted session holds, kept up to date as each state is
/// accepted, so the state an edit makes is checked only for what the edit
/// changed. A workspace holds a session only when every Space, profile, tab and
/// Space deletion has an identity, no two Spaces share an identity or a
/// profile, no two tabs share an identity, and each Space deletion names a
/// Space the session holds, with its profile, once.
///
/// An edit keeps every Space it leaves alone as the same object, so the rules
/// about Spaces are checked again only when a Space's identity or profile, the
/// list of Spaces or the deletions changed, and they read only the Spaces'
/// headers. Tab identities are checked only in the Spaces an edit replaced, and
/// only between the first and the last tab whose identity changed there,
/// against the identities every other tab keeps. A state that breaks a rule is
/// named by the full check, so an edit is refused for the same flaw a whole
/// session would be.
internal sealed class SessionIdentities {
    #region Types

    /// What an edit that breaks no rule changed of the tab identities, from
    /// `Basis` to `Next`: the ones it took out and put in, which may share a
    /// moved tab, and the Spaces whose tabs it read.
    internal sealed record Step(SessionState Basis, SessionState Next, IReadOnlyList<Guid> Removed, IReadOnlyList<Guid> Added,
        IReadOnlyList<Guid> Examined);

    #endregion

    #region Variables

    /// Every tab identity `indexed` holds.
    private readonly HashSet<Guid> tabs = [];
    /// The state `tabs` describes, which breaks no rule, or null when none does.
    private SessionState? indexed;

    /// The last step an edit was checked with, which accepting its state takes
    /// instead of comparing the two states again.
    internal Step? Last { get; private set; }

    #endregion

    #region Actions - Whole sessions

    /// The first rule `value` breaks that keeps a workspace from holding it, in
    /// session order, or null for a session a workspace can hold. It reads every
    /// tab, as a session that arrives whole needs.
    internal static SessionFlaw? Flaw(SessionState value) => Flaw(value, []);

    /// Checks `value` whole and describes it from now on; answers the first rule
    /// it breaks, and then describes no state.
    internal SessionFlaw? Index(SessionState value) {
        ArgumentNullException.ThrowIfNull(value);
        tabs.Clear();
        indexed = null;
        Last = null;
        if (Flaw(value, tabs) is { } flaw) {
            tabs.Clear();
            return flaw;
        }
        indexed = value;
        return null;
    }

    /// The whole check, which adds every tab identity `value` holds to `tabs`
    /// as it reads them.
    private static SessionFlaw? Flaw(SessionState value, HashSet<Guid> tabs) {
        var ids = new HashSet<Guid>(); var profiles = new HashSet<Guid>();
        foreach (var space in value.Spaces) {
            if (space.Id == Guid.Empty || space.ProfileId == Guid.Empty || space.Tabs.Any(tab => tab.Id == Guid.Empty))
                return SessionFlaw.MissingIdentity;
            if (!ids.Add(space.Id)) return SessionFlaw.DuplicateSpace;
            // A Space is exactly one profile and a profile belongs to exactly one
            // Space. Two Spaces sharing a profile would share cookies, credentials
            // and extension access across an isolation boundary the user relies on,
            // and would make "which Space owns this profile" unanswerable.
            if (!profiles.Add(space.ProfileId)) return SessionFlaw.SharedProfile;
            foreach (var tab in space.Tabs)
                if (!tabs.Add(tab.Id)) return SessionFlaw.DuplicateTab;
        }
        return DeletionFlaw(value);
    }

    #endregion

    #region Actions - Edits

    /// The first rule `next`, an edit of `basis`, breaks, or null for a session
    /// a workspace can hold. When this describes `basis`, only what the edit
    /// changed is read; otherwise `next` is checked whole.
    internal SessionFlaw? Flaw(SessionState basis, SessionState next) {
        ArgumentNullException.ThrowIfNull(basis);
        ArgumentNullException.ThrowIfNull(next);
        if (!ReferenceEquals(indexed, basis)) return Flaw(next);
        var step = Stepping(basis, next);
        Last = step;
#if CREST_CROSS_CHECKS
        var whole = Flaw(next);
        if (step is null != whole is not null)
            throw new UnreachableException(
                $"The edit's check found {(step is null ? "a flaw" : "no flaw")}, and the whole session's found {whole?.ToString() ?? "none"}.");
        return whole;
#else
        return step is null ? Flaw(next) : null;
#endif
    }

    /// Follows the session from `previous`, the state this describes, to
    /// `next`, the state it accepted. A state accepted from one this does not
    /// describe is checked and indexed whole.
    internal void Accepted(SessionState previous, SessionState next) {
        ArgumentNullException.ThrowIfNull(previous);
        ArgumentNullException.ThrowIfNull(next);
        if (ReferenceEquals(indexed, next)) return;
        var step = Last is { } last && ReferenceEquals(last.Basis, previous) && ReferenceEquals(last.Next, next) ? last
            : ReferenceEquals(indexed, previous) ? Stepping(previous, next) : null;
        if (step is null) {
            _ = Index(next);
            return;
        }
        foreach (var id in step.Removed) tabs.Remove(id);
        foreach (var id in step.Added) tabs.Add(id);
        indexed = next;
        Last = step;
#if CREST_CROSS_CHECKS
        if (!tabs.SetEquals(next.Spaces.SelectMany(space => space.Tabs).Select(tab => tab.Id)))
            throw new UnreachableException("The session's tab identities no longer match the tabs it holds.");
#endif
    }

    /// What the edit from `basis`, the state this describes, to `next` changed
    /// of the tab identities, or null when `next` breaks a rule.
    private Step? Stepping(SessionState basis, SessionState next) {
        List<Guid> removed = [], added = [], examined = [];
        var before = basis.Spaces;
        var after = next.Spaces;
        var aligned = before.Count == after.Count;
        for (var index = 0; aligned && index < after.Count; index++) aligned = before[index].Id == after[index].Id;
        var headersChanged = !aligned;
        if (aligned) {
            for (var index = 0; index < after.Count; index++) {
                var (was, space) = (before[index], after[index]);
                if (ReferenceEquals(was, space)) continue;
                headersChanged |= was.ProfileId != space.ProfileId;
                Compare(was, space, removed, added, examined);
            }
        } else {
            var earlier = before.ToDictionary(space => space.Id);
            foreach (var space in after) {
                if (earlier.Remove(space.Id, out var was)) {
                    if (!ReferenceEquals(was, space)) Compare(was, space, removed, added, examined);
                    continue;
                }
                examined.Add(space.Id);
                added.AddRange(space.Tabs.Select(tab => tab.Id));
            }
            foreach (var gone in earlier.Values) {
                examined.Add(gone.Id);
                removed.AddRange(gone.Tabs.Select(tab => tab.Id));
            }
        }
        if (headersChanged && HeaderFlaw(next) is not null) return null;
        if ((headersChanged || !ReferenceEquals(basis.SpaceDeletions, next.SpaceDeletions)
            && !basis.SpaceDeletions.SequenceEqual(next.SpaceDeletions)) && DeletionFlaw(next) is not null) return null;
        // Every identity the basis holds is unique, and every one the edit kept
        // stays: an identity it put in must be new, or one it took out.
        if (added.Count > 0) {
            HashSet<Guid>? leaving = removed.Count == 0 ? null : [.. removed];
            var entering = new HashSet<Guid>(added.Count);
            foreach (var id in added)
                if (id == Guid.Empty || !entering.Add(id) || tabs.Contains(id) && leaving?.Contains(id) != true) return null;
        }
        return new(basis, next, removed, added, examined);
    }

    /// Adds the tab identities that `space`, a new state of `was`, took out and
    /// put in: the ones between the first and last tab whose identity changed.
    /// Tabs whose identity stays in place are only compared.
    private static void Compare(SpaceState was, SpaceState space, List<Guid> removed, List<Guid> added, List<Guid> examined) {
        var (before, after) = (was.Tabs, space.Tabs);
        if (ReferenceEquals(before, after)) return;
        examined.Add(space.Id);
        var shorter = Math.Min(before.Count, after.Count);
        var start = 0;
        while (start < shorter && Kept(before[start], after[start])) start++;
        var end = 0;
        while (end < shorter - start && Kept(before[before.Count - 1 - end], after[after.Count - 1 - end])) end++;
        for (var index = start; index < before.Count - end; index++) removed.Add(before[index].Id);
        for (var index = start; index < after.Count - end; index++) added.Add(after[index].Id);
    }

    private static bool Kept(TabState before, TabState after) => ReferenceEquals(before, after) || before.Id == after.Id;

    #endregion

    #region Actions - Rules

    /// The first rule the Spaces' own identities and profiles break, reading
    /// only each Space's header.
    private static SessionFlaw? HeaderFlaw(SessionState value) {
        var ids = new HashSet<Guid>(); var profiles = new HashSet<Guid>();
        foreach (var space in value.Spaces) {
            if (space.Id == Guid.Empty || space.ProfileId == Guid.Empty) return SessionFlaw.MissingIdentity;
            if (!ids.Add(space.Id)) return SessionFlaw.DuplicateSpace;
            if (!profiles.Add(space.ProfileId)) return SessionFlaw.SharedProfile;
        }
        return null;
    }

    /// The first rule the Space deletions break against the Spaces the session
    /// holds.
    private static SessionFlaw? DeletionFlaw(SessionState value) {
        var pendingIds = new HashSet<Guid>();
        foreach (var deletion in value.SpaceDeletions) {
            if (deletion.Id == Guid.Empty || deletion.SpaceId == Guid.Empty || deletion.ProfileId == Guid.Empty)
                return SessionFlaw.MissingIdentity;
            if (!pendingIds.Add(deletion.SpaceId)
                || !value.Spaces.Any(space => space.Id == deletion.SpaceId && space.ProfileId == deletion.ProfileId))
                return SessionFlaw.UnknownDeletion;
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
        return null;
    }

    #endregion
}
