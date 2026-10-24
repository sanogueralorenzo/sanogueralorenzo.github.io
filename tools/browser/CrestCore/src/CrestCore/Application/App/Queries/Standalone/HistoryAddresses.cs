using CrestCore.Application;

namespace CrestCore.Contracts;

/// The address history keeps for each of `Addresses`, as `WebAddress`
/// normalizes it: an http or https address without its fragment, or none. It
/// reads no state, so a host may ask it without an app.
public sealed record HistoryAddresses(IReadOnlyList<string> Addresses) : StandaloneQuery<HistoryAddressList> {
    #region Actions - Answering

    internal override HistoryAddressList Answer(StandaloneContext context) =>
        new([.. Addresses.Select(address => new WebAddress(address).Normalized)]);

    #endregion
}
