namespace CrestCore.Contracts;

/// A tab group's color as Chrome names it, which an extension reads and sets
/// through `chrome.tabGroups`, and the color the folder that shows a group
/// takes. The tab groups releases before folders stored spell a color as its
/// `Name`, so a name never changes. A color travels as its index in `All`, in
/// the order of Chromium's own color identities, so `All` is append-only.
public sealed class TabGroupColor {
    #region Static Variables

    public static readonly TabGroupColor Grey = new(name: "grey", color: new(0.56, 0.56, 0.58));
    public static readonly TabGroupColor Blue = new(name: "blue", color: new(0.04, 0.52, 1));
    public static readonly TabGroupColor Red = new(name: "red", color: new(1, 0.27, 0.23));
    public static readonly TabGroupColor Yellow = new(name: "yellow", color: new(1, 0.84, 0.04));
    public static readonly TabGroupColor Green = new(name: "green", color: new(0.19, 0.82, 0.35));
    public static readonly TabGroupColor Pink = new(name: "pink", color: new(1, 0.22, 0.37));
    public static readonly TabGroupColor Purple = new(name: "purple", color: new(0.75, 0.35, 0.95));
    public static readonly TabGroupColor Cyan = new(name: "cyan", color: new(0.39, 0.82, 1));
    public static readonly TabGroupColor Orange = new(name: "orange", color: new(0.91, 0.43, 0.23));

    public static IReadOnlyList<TabGroupColor> All { get; } = [Grey, Blue, Red, Yellow, Green, Pink, Purple, Cyan, Orange];

    #endregion

    #region Variables

    public string Name { get; }

    /// The color a folder takes for a group of this color.
    public BrandColor Color { get; }

    #endregion

    #region Constructors

    private TabGroupColor(string name, BrandColor color) {
        Name = name;
        Color = color;
    }

    #endregion

    #region Actions - Lookup

    public static TabGroupColor? Named(string? name) => All.FirstOrDefault(color => color.Name == name);

    /// The group color closest to `color`, which is how a folder's own color
    /// reads to an extension: each group color is closest to itself.
    public static TabGroupColor Nearest(BrandColor color) => All.MinBy(candidate => candidate.Distance(color))!;

    /// How far `other` is from this color, by its red, green and blue.
    private double Distance(BrandColor other) =>
        Math.Pow(Color.Red - other.Red, 2) + Math.Pow(Color.Green - other.Green, 2) + Math.Pow(Color.Blue - other.Blue, 2);

    #endregion
}
