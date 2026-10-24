using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A row that opens the address the pasteboard held when the palette opened,
/// when it held one and not words to search, while the person has not
/// changed the text the palette opened with: nothing, or the address of the
/// page the window shows.
internal sealed class PasteFinder : PaletteFinder {
    #region Static Variables

    /// The longest pasteboard text the palette reads as an address.
    private const int MaximumLength = 2_048;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteRow> RestingOffers(PaletteContext context, PaletteSuggestions question) => Pasted(context, question);

    internal override IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) =>
        Pasted(context, question);

    private static IEnumerable<PaletteRow> Pasted(PaletteContext context, PaletteSuggestions question) {
        if (question.Pasteboard is not { Length: <= MaximumLength } pasteboard) yield break;
        AddressResolution? resolution;
        try {
            resolution = AddressResolution.Resolve(pasteboard.Trim(), context.Search, context.AllowsInternalPages);
        } catch (Rejected refused) when (refused.Rejection is UnsupportedAddress) {
            yield break;
        }
        if (resolution is not { SearchQuery: null } || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out _)) yield break;
        yield return PaletteRow.Of(PaletteRowKind.PasteAndGo, "Paste and Go", resolution.Url, address: resolution.Url);
    }

    #endregion
}
