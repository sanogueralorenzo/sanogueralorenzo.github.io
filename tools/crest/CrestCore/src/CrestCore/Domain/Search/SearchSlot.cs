namespace CrestCore.Domain;

/// A named place in a built-in provider's search address that differs by
/// where or how a person searches: the host DuckDuckGo answers on, the
/// language of Wikipedia or MDN, Amazon's store, the kind of result Spotify
/// lists. The address spells a slot as its token, an option fills it, and the
/// provider says what it holds when no option does.
internal sealed class SearchSlot {
    #region Static Variables

    public static readonly SearchSlot Host = new("{host}");
    public static readonly SearchSlot Language = new("{language}");
    public static readonly SearchSlot Locale = new("{locale}");
    public static readonly SearchSlot Store = new("{store}");
    public static readonly SearchSlot Category = new("{category}");

    public static IReadOnlyList<SearchSlot> All { get; } = [Host, Language, Locale, Store, Category];

    #endregion

    #region Variables

    /// How a search address spells the slot.
    public string Token { get; }

    #endregion

    #region Constructors

    private SearchSlot(string token) => Token = token;

    #endregion

    #region Actions - Filling

    /// What the slot holds when nothing fills it.
    public SearchSlotDefault Holding(string value) => new(this, value);

    #endregion
}

/// What `Slot` holds in a provider's address when no option fills it.
internal sealed record SearchSlotDefault(SearchSlot Slot, string Value);
