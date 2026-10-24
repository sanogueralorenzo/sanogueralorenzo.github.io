using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether two addresses name one page, as `WebAddress.IsSamePage` decides.
/// It reads no state, so a host may ask it without an app.
public sealed record SamePage(string First, string Second) : StandaloneQuery<PageMatch> {
    #region Actions - Answering

    internal override PageMatch Answer(StandaloneContext context) => new(new WebAddress(First).IsSamePage(new WebAddress(Second)));

    #endregion
}
