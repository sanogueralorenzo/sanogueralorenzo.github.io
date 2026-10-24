using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The session `Seed` opens as, repaired as a stored session is when it loads
/// and resolved, for a view that shows Spaces no workspace holds: a preview,
/// or a draft before it is saved. Nothing opens, so no change of it is ever
/// published. It reads no state, so a host may ask it without an app.
public sealed record DetachedSession(SessionState Seed) : StandaloneQuery<SessionState> {
    #region Actions - Answering

    /// The seed repaired as a stored session is when it loads, stamped as the
    /// session stores the time. Throws `Rejected` with `InvalidSession`
    /// naming the first rule it breaks that the repair cannot mend.
    internal override SessionState Answer(StandaloneContext context) {
        var now = StoredSessionCodec.Date(StoredSessionCodec.Seconds(context.Now));
        SessionState repaired;
        try {
            repaired = NativeSessionMaintenance.Repair(Seed, now, null, new SystemIdSource(), out _);
        } catch (BrowserRuleException) {
            throw new Rejected(new InvalidSession(SessionIdentities.Flaw(Seed) ?? SessionFlaw.Unreadable));
        }
        return SessionIdentities.Flaw(repaired) is { } flaw ? throw new Rejected(new InvalidSession(flaw)) : repaired;
    }

    #endregion
}
