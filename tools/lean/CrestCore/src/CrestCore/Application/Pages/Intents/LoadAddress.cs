using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Asks a page to load an address Crest already holds, such as its tab's
/// stored location or one it returns to, rather than words a person typed.
/// An absolute address in a scheme the engine keeps loads as it is, whatever
/// its length or spelling; anything else is resolved as `Navigate` resolves
/// input. Refused as `Navigate` is.
public sealed record LoadAddress(Guid PageId, string Url) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) =>
        Navigate.Load(pages, turn, PageId, (provider, showsInternalPages) =>
            AddressResolution.Held(Url, showsInternalPages) ?? AddressResolution.Loading(Url, provider, showsInternalPages));

    #endregion
}
