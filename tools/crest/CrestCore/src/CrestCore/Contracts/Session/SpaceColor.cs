namespace CrestCore.Contracts;

/// The fixed colors a Space can use for its dot.
public sealed class SpaceColor {
    #region Static Variables

    public static readonly SpaceColor Blue = new("blue", "Blue", new(0.23, 0.53, 0.96));
    public static readonly SpaceColor Teal = new("teal", "Teal", new(0.06, 0.69, 0.65));
    public static readonly SpaceColor Green = new("green", "Green", new(0.2, 0.73, 0.37));
    public static readonly SpaceColor Amber = new("amber", "Amber", new(0.96, 0.66, 0.16));
    public static readonly SpaceColor Coral = new("coral", "Coral", new(0.96, 0.4, 0.36));
    public static readonly SpaceColor Purple = new("purple", "Purple", new(0.65, 0.39, 0.92));

    public static IReadOnlyList<SpaceColor> All { get; } = [Blue, Teal, Green, Amber, Coral, Purple];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized] public string Title { get; }
    public BrandColor Tint { get; }

    #endregion

    #region Constructors

    private SpaceColor(string name, string title, BrandColor tint) {
        Name = name;
        Title = title;
        Tint = tint;
    }

    #endregion

    #region Actions - Selection

    public static SpaceColor? Named(string? name) => All.FirstOrDefault(color => color.Name == name);

    /// Prefer the least-used color when adding a Space.
    public static SpaceColor Next(IEnumerable<SpaceColor> used) {
        var colors = used.ToArray();
        return All.MinBy(color => colors.Count(chosen => chosen == color))!;
    }

    /// A stable initial color for a Space that has no color saved yet.
    public static SpaceColor For(Guid id) => All[id.ToByteArray()[0] % All.Count];

    #endregion
}
