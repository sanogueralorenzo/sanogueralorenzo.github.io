using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Page edits

    /// Applies what a page's engine reported to the Space the page lives in,
    /// as one revision saved behind and staged once page reports pause, and
    /// answers the changes the caller publishes. Reports and intents take the
    /// app's lock, so no intent holds the session while a report applies. One
    /// that no longer applies changes nothing: its Space is gone, locked or
    /// being deleted, its tab is gone, or the session takes no edits.
    internal IReadOnlyList<Change> Apply(PageEdit edit) {
        ArgumentNullException.ThrowIfNull(edit);
        (SessionState Previous, SessionState Next, SessionTabEvents Events)? applied;
        Guid workspace;
        lock (Gate) {
            applied = ApplyUnderGate(edit);
            workspace = workspaceId;
        }
        if (applied is not { } result) return [];
        QueueStage(result.Previous, result.Next, SyncStaging.PageReport);
        return [.. SessionChanges.Publish(workspace, result.Previous, result.Next), .. result.Events.Changes(workspace),
            .. edit.Announced(workspace)];
    }

    /// Starts `copy`, a new copy of `sourceId`, from the address and title
    /// the source's page shows now, preferring the page `windowId` hosts,
    /// since a page can move on before its navigation is recorded. A copy of
    /// a source without a page, or of one that is not a web page, keeps what
    /// the session holds.
    internal void StartFromSourcePage(BrowserTab copy, Guid sourceId, Guid windowId, Pages? pages) {
        if (copy.Content.IsWebPage && pages?.Showing(workspaceId, windowId, sourceId) is { } shown)
            copy.ObserveAppearance(shown.Address, shown.Title);
    }

    /// Accepts `edit` and answers the states it went between, or null when it
    /// no longer applies, including when a rule would refuse what it leaves:
    /// a report is never refused. An edit that changes nothing is still
    /// taken: the state stays as it was. The caller holds the gate.
    private (SessionState Previous, SessionState Next, SessionTabEvents Events)? ApplyUnderGate(PageEdit edit) {
        if (!TakesEdits() || session.PendingDeletion(edit.SpaceId) is not null
            || session.Space(edit.SpaceId) is not { } original
            || IsLockedUnderGate(original)) return null;
        SessionState next;
        SessionTabEvents events;
        try {
            if (edit.Apply(original, Stamp(edit.At)) is not { } edited) return null;
            events = new SessionTabEvents([], edited.Favicon);
            if (edited.Space == original) return (session, session, events);
            next = session.Replacing(edited.Space);
            Validate(session, next);
            ValidateBorrowedSession(next);
        } catch (Rejected) {
            return null;
        }
        return (Accept(next), next, events);
    }

    #endregion
}
