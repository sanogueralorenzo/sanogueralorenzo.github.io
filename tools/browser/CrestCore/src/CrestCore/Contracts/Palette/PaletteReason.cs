namespace CrestCore.Contracts;

/// Why the palette ranked a row where it did: the strongest signal that
/// raised it. VoiceOver reads it, and the palette shows it under the row when
/// the person asked to see match reasons. A reason travels as its index
/// in `All`, so `All` is append-only.
public sealed class PaletteReason {
    #region Static Variables

    public static readonly PaletteReason Completion = new(name: "completion", text: "Completes what you typed");
    public static readonly PaletteReason Learned = new(name: "learned", text: "You chose this before");
    public static readonly PaletteReason OftenVisited = new(name: "oftenVisited", text: "Often visited");
    public static readonly PaletteReason RecentlyUsed = new(name: "recentlyUsed", text: "Recently used");
    public static readonly PaletteReason OpenTab = new(name: "openTab", text: "Already open");
    public static readonly PaletteReason Kept = new(name: "kept", text: "Pinned or saved");
    public static readonly PaletteReason TitleMatch = new(name: "titleMatch", text: "Matches the title");
    public static readonly PaletteReason AddressMatch = new(name: "addressMatch", text: "Matches the address");

    public static IReadOnlyList<PaletteReason> All { get; } =
        [Completion, Learned, OftenVisited, RecentlyUsed, OpenTab, Kept, TitleMatch, AddressMatch];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the palette says about the row.
    [Localized]
    public string Text { get; }

    #endregion

    #region Constructors

    private PaletteReason(string name, string text) {
        Name = name;
        Text = text;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion
}
