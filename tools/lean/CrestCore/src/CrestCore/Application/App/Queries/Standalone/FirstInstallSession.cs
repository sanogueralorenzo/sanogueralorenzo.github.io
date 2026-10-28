using CrestCore.Application;

namespace CrestCore.Contracts;

/// The session a first launch starts with when nothing is carried to it: one
/// Personal Space wearing the Winter house look, showing a Start Page, marked
/// as the disposable first-install seed. A file that holds no session takes it
/// from `AdoptLegacySession` without a seed; a launch without a file opens it
/// as the seed of an `OpenWorkspace`. It reads no state, so a host may ask it
/// without an app.
public sealed record FirstInstallSession() : StandaloneQuery<SessionState> {
    #region Actions - Answering

    internal override SessionState Answer(StandaloneContext context) => FirstSession.FirstInstall(Guid.NewGuid, context.Now);

    #endregion
}
