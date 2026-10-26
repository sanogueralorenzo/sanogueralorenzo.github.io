namespace CrestCore.Contracts;

/// Which source fills a tab's icon slot: the page's own favicon as it changes,
/// a favicon pulled once and kept, or a chosen emoji. The image bytes never
/// reach the core: a tab's icon is a stored mode, a symbol and the address the
/// cached image was pulled from, and those three decide everything.
///
/// The stored session spells a mode as its `Name`, so a name never changes.
/// A mode travels as its index in `All`, so `All` is append-only.
public sealed class TabIconMode {
    #region Static Variables

    /// One storage slot holds either an SF Symbol name or an emoji, so the
    /// emoji spelling carries this prefix, which makes the two unambiguous.
    public const string EmojiPrefix = "crest.emoji:";

    /// The symbol a tab shows while its icon comes from a favicon.
    public const string WebSymbol = "globe";

    public static readonly TabIconMode Automatic = new(name: "automatic", inferencePrefix: "", followsPage: true);
    public static readonly TabIconMode Pulled = new(name: "pulled", inferencePrefix: null);
    public static readonly TabIconMode Emoji = new(name: "emoji", inferencePrefix: EmojiPrefix, showsFavicon: false);

    public static IReadOnlyList<TabIconMode> All { get; } = [Automatic, Pulled, Emoji];

    #endregion

    #region Variables

    public string Name { get; }

    /// The symbol prefix that marks a tab written without a stored mode as
    /// being in this mode, when something follows it. An empty prefix claims
    /// any symbol, and null claims none. The longest prefix a symbol carries
    /// wins.
    public string? InferencePrefix { get; }

    /// The page's favicon replaces the icon as the page changes.
    public bool FollowsPage { get; }

    /// The tab shows its cached favicon rather than its symbol.
    public bool ShowsFavicon { get; }

    #endregion

    #region Constructors

    private TabIconMode(string name, string? inferencePrefix, bool followsPage = false, bool showsFavicon = true) {
        Name = name;
        InferencePrefix = inferencePrefix;
        FollowsPage = followsPage;
        ShowsFavicon = showsFavicon;
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
}
