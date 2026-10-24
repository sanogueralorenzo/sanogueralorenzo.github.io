namespace CrestCore.Contracts;

/// Which source fills a tab's icon slot: the page's own favicon as it changes,
/// a favicon pulled once and kept, or a chosen emoji. The image bytes never
/// reach the core: a tab's icon is a stored mode, a symbol and the address the
/// cached image was pulled from, and those three decide everything.
///
/// The stored session spells a mode as its `Name`, so a name never changes.
/// A mode travels as its index in `All`, so `All` is append-only.
public sealed class TabIconMode {
    #region Variables

    /// One storage slot holds either an SF Symbol name or an emoji, so the
    /// emoji spelling carries this prefix, which makes the two unambiguous.
    public const string EmojiPrefix = "crest.emoji:";

    /// The symbol a tab shows while its icon comes from a favicon.
    public const string WebSymbol = "globe";

    public static readonly TabIconMode Automatic = new(name: "automatic", inferencePrefix: "", followsPage: true,
        symbol: _ => WebSymbol);
    public static readonly TabIconMode Pulled = new(name: "pulled", inferencePrefix: null, requiresFavicon: true, symbol: _ => WebSymbol);
    public static readonly TabIconMode Emoji = new(name: "emoji", inferencePrefix: EmojiPrefix, showsFavicon: false,
        symbol: emoji => EmojiIcon.Chosen(emoji)?.Symbol);

    public static IReadOnlyList<TabIconMode> All { get; } = [Automatic, Pulled, Emoji];

    private readonly Func<string?, string?> symbol;

    public string Name { get; }

    /// The symbol prefix that marks a tab written without a stored mode as
    /// being in this mode, when something follows it. An empty prefix claims
    /// any symbol, and null claims none. The longest prefix a symbol carries
    /// wins.
    public string? InferencePrefix { get; }

    /// The page's favicon replaces the icon as the page changes.
    public bool FollowsPage { get; }

    /// Choosing the mode pulls the page's favicon, so it needs one.
    public bool RequiresFavicon { get; }

    /// The tab shows its cached favicon rather than its symbol.
    public bool ShowsFavicon { get; }

    #endregion

    #region Constructors

    private TabIconMode(string name, string? inferencePrefix, Func<string?, string?> symbol, bool followsPage = false,
        bool requiresFavicon = false, bool showsFavicon = true) {
        Name = name;
        InferencePrefix = inferencePrefix;
        FollowsPage = followsPage;
        RequiresFavicon = requiresFavicon;
        ShowsFavicon = showsFavicon;
        this.symbol = symbol;
    }

    #endregion

    #region Actions - Lookup

    public static TabIconMode? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);

    /// The mode of a tab written before modes were stored, or whose stored
    /// term this build cannot name, taken from its own symbol, so an unfamiliar
    /// term never pins a tab to a mode it did not choose.
    public static TabIconMode Inferred(string? symbol) =>
        All.Where(mode => mode.Claims(symbol)).MaxBy(mode => mode.InferencePrefix!.Length)!;

    private bool Claims(string? symbol) => InferencePrefix is { } prefix && (prefix.Length == 0
        || symbol is not null && symbol.Length > prefix.Length && symbol.StartsWith(prefix, StringComparison.Ordinal));

    #endregion

    #region Actions - Icons

    /// The symbol a tab stores when the person chooses this mode, or null when
    /// the mode needs an emoji and none was given. Emoji text normalization
    /// stays with the platform that owns grapheme handling.
    public string? Symbol(string? emoji) => symbol(emoji);

    #endregion
}
