using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether the core would accept a session intent now, and when it would not,
/// the rule that would refuse it. Nothing changes, so a menu can ask the
/// core's own rules, such as a folder's depth or a split's size, before it
/// offers an action.
public sealed record CanSend(Intent Intent) : Query<SendPermission> {
    #region Actions - Answering

    /// Whether the core would accept a session intent now: the rule that would
    /// refuse it, or none. The identities a check draws are never used.
    internal override SendPermission Answer(CrestApp app) {
        if (Intent is not SessionIntent session)
            throw new ArgumentOutOfRangeException(nameof(Intent), Intent.GetType().Name, "Only a session intent can be checked.");
        try {
            app.Device.Workspace(session.WorkspaceId).Check(session, app.Clock.Now, new SystemIdSource(), app.Pages);
            return new(Refusal: null);
        } catch (Rejected refused) {
            return new(refused.Rejection);
        }
    }

    #endregion
}
