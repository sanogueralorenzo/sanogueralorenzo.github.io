using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// What a person chose for a split, as a Crest browser-data file keeps it.
internal sealed record BrowserDataSplit(Guid Id, string? CustomTitle, DateTimeOffset? TitleModifiedAt, string? CustomIconSymbol,
    DateTimeOffset? IconModifiedAt, BrandColor? Tint, DateTimeOffset? TintModifiedAt) {
    #region Actions - Reading

    public static BrowserDataSplit Read(BrowserDataValue value) => new(value.Identity("id"), value.OptionalText("customTitle"),
        value.OptionalDate("titleModifiedAt"), value.OptionalText("customIconSymbol"), value.OptionalDate("iconModifiedAt"),
        value.OptionalColor("tint"), value.OptionalDate("tintModifiedAt"));

    /// The split a Space keeps, with its new identity: a blank title is none,
    /// the icon is spelled as an emoji icon, and each edit time is whole
    /// milliseconds. Throws `ArchiveInvalid` for a title or icon a Space would
    /// not keep, or an icon that is no emoji.
    public SplitGroupState Materialize(Guid id) {
        if (CustomTitle is not null && !ImportText.IsKept(CustomTitle, ImportText.MaximumTitle)) throw BrowserDataValue.Invalid();
        string? icon = null;
        if (CustomIconSymbol is not null) {
            if (!ImportText.IsKept(CustomIconSymbol, ImportText.MaximumSymbol)) throw BrowserDataValue.Invalid();
            icon = EmojiIcon.Parse(CustomIconSymbol)?.Symbol ?? throw BrowserDataValue.Invalid();
        }
        string? title = string.IsNullOrWhiteSpace(CustomTitle) ? null : CustomTitle.Trim();
        return new(id, title, WholeMilliseconds(TitleModifiedAt), icon, WholeMilliseconds(IconModifiedAt), Tint,
            WholeMilliseconds(TintModifiedAt));
    }

    private static DateTimeOffset? WholeMilliseconds(DateTimeOffset? date) =>
        date is { } value ? ImportDate.FromUnixMilliseconds(Math.Round(ImportDate.UnixMilliseconds(value), MidpointRounding.AwayFromZero))
            : null;

    #endregion

    #region Actions - Writing

    public static BrowserDataSplit From(SplitGroupState split) {
        ArgumentNullException.ThrowIfNull(split);
        return new(split.Id, split.CustomTitle, split.TitleModifiedAt, split.CustomIconSymbol, split.IconModifiedAt, split.Tint,
            split.TintModifiedAt);
    }

    public JsonObject Write() {
        var value = new JsonObject { ["id"] = BrowserDataFile.Identity(Id) };
        if (CustomTitle is not null) value["customTitle"] = CustomTitle;
        if (TitleModifiedAt is { } title) value["titleModifiedAt"] = ImportDate.UnixMilliseconds(title);
        if (CustomIconSymbol is not null) value["customIconSymbol"] = CustomIconSymbol;
        if (IconModifiedAt is { } icon) value["iconModifiedAt"] = ImportDate.UnixMilliseconds(icon);
        if (Tint is { } tint) value["tint"] = BrowserDataFile.Color(tint);
        if (TintModifiedAt is { } tinted) value["tintModifiedAt"] = ImportDate.UnixMilliseconds(tinted);
        return value;
    }

    #endregion
}
