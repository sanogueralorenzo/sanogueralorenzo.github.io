using System.Text;

namespace CrestCore.Contracts;

/// <summary>
/// A folder in a Space's saved or open section. Folders form a forest through
/// <see cref="ParentId"/>, and a child always shares its parent's <see cref="Location"/>.
/// <see cref="Symbol"/> and <see cref="Color"/> are null until someone chooses them.
/// <see cref="OrderAnchorTabId"/> is the tab an empty folder keeps its place before.
/// </summary>
[Observed]
public sealed record FolderState(
    Guid Id,
    TabPlacement Location,
    string Title,
    string? Symbol = null,
    BrandColor? Color = null,
    Guid? ParentId = null,
    bool IsCollapsed = false,
    DateTimeOffset? CollapseModifiedAt = null,
    Guid? OrderAnchorTabId = null) {
    #region Static Variables

    /// The most folders deep a folder may nest, counting the folder itself.
    public const int MaximumDepth = 16;

    /// The SF Symbol a folder shows until someone chooses one.
    public const string DefaultSymbol = "folder";

    /// The color a folder the core makes for a person's tabs is drawn in, and the one
    /// a folder shows until someone chooses one.
    public static BrandColor DefaultColor { get; } = new(0.43, 0.48, 0.54);

    #endregion

    #region Variables

    /// The symbol the folder shows: the one chosen, or <see cref="DefaultSymbol"/>.
    [Resolved]
    public string DisplaySymbol => Symbol ?? DefaultSymbol;

    /// The color the folder is drawn in: the one chosen, or <see cref="DefaultColor"/>.
    [Resolved]
    public BrandColor DisplayColor => Color ?? DefaultColor;

    #endregion

    #region Actions - Imports

    /// The key an imported folder matches an existing one by: its letters and
    /// digits in compatibility form, lowercased.
    internal static string MatchKey(string title) => string.Concat(title.Normalize(NormalizationForm.FormKD)
        .Where(char.IsLetterOrDigit)).ToLowerInvariant();

    #endregion
}
