using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One split's synced metadata: its name, emoji icon and tint, each with the
/// clock of its last edit, so edits on different devices merge per field.
internal sealed record SplitGroupPayload(
    Guid Id,
    string? CustomTitle,
    SyncTime? TitleModifiedAt,
    string? CustomIconSymbol,
    SyncTime? IconModifiedAt,
    BrandColor? Tint,
    SyncTime? TintModifiedAt) {
    #region Static Variables

    /// The members a split's metadata carries; a record keeps what a newer
    /// build writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.CustomTitle, StoredSessionCodec.Key.TitleModifiedAt,
        StoredSessionCodec.Key.CustomIconSymbol, StoredSessionCodec.Key.IconModifiedAt, StoredSessionCodec.Key.Tint,
        StoredSessionCodec.Key.TintModifiedAt
    ];

    #endregion

    #region Actions - Coding

    /// The splits `groups` names, as every client reads them: a blank name is
    /// none, an icon that is no emoji is none, each clock is whole
    /// milliseconds, and a split named twice keeps each field from the copy
    /// that edited it later, the later copy winning a tie.
    public static IReadOnlyList<SplitGroupPayload> Normalized(JsonArray groups, SyncPayloadForm form) {
        var result = new List<SplitGroupPayload>();
        var positions = new Dictionary<Guid, int>();
        foreach (var item in groups) {
            var candidate = Read(new SyncPayloadReader(item, form));
            if (positions.TryGetValue(candidate.Id, out int position)) result[position] = candidate.Merged(result[position]);
            else {
                positions[candidate.Id] = result.Count;
                result.Add(candidate);
            }
        }
        return result;
    }

    /// One split as every client reads it; see `Normalized`.
    private static SplitGroupPayload Read(SyncPayloadReader value) {
        string? title = value.OptionalText(StoredSessionCodec.Key.CustomTitle)?.Trim();
        return new(value.WrappedIdentity(StoredSessionCodec.Key.Id), string.IsNullOrEmpty(title) ? null : title,
            value.OptionalTime(StoredSessionCodec.Key.TitleModifiedAt)?.ToWholeMilliseconds(),
            EmojiIcon.Parse(value.OptionalText(StoredSessionCodec.Key.CustomIconSymbol)) is { } icon
                ? TabIconMode.EmojiPrefix + icon.Emoji : null,
            value.OptionalTime(StoredSessionCodec.Key.IconModifiedAt)?.ToWholeMilliseconds(),
            value.Value[StoredSessionCodec.Key.Tint] is { } tint ? SpacePayload.Color(tint) : null,
            value.OptionalTime(StoredSessionCodec.Key.TintModifiedAt)?.ToWholeMilliseconds());
    }

    public JsonObject Encode(SyncPayloadForm form) {
        var value = new JsonObject { [StoredSessionCodec.Key.Id] = StoredSessionCodec.WrappedIdentity(Id) };
        if (CustomTitle is not null) value[StoredSessionCodec.Key.CustomTitle] = CustomTitle;
        if (TitleModifiedAt is { } titled) value[StoredSessionCodec.Key.TitleModifiedAt] = form.Seconds(titled);
        if (CustomIconSymbol is not null) value[StoredSessionCodec.Key.CustomIconSymbol] = CustomIconSymbol;
        if (IconModifiedAt is { } iconed) value[StoredSessionCodec.Key.IconModifiedAt] = form.Seconds(iconed);
        if (Tint is { } tint) value[StoredSessionCodec.Key.Tint] = StoredSessionCodec.Encode(tint);
        if (TintModifiedAt is { } tinted) value[StoredSessionCodec.Key.TintModifiedAt] = form.Seconds(tinted);
        return value;
    }

    /// This split, preferred, with each field `older` edited later.
    private SplitGroupPayload Merged(SplitGroupPayload older) {
        var titled = Later(TitleModifiedAt, older.TitleModifiedAt) ? older : this;
        var iconed = Later(IconModifiedAt, older.IconModifiedAt) ? older : this;
        var tinted = Later(TintModifiedAt, older.TintModifiedAt) ? older : this;
        return this with {
            CustomTitle = titled.CustomTitle,
            TitleModifiedAt = titled.TitleModifiedAt,
            CustomIconSymbol = iconed.CustomIconSymbol,
            IconModifiedAt = iconed.IconModifiedAt,
            Tint = tinted.Tint,
            TintModifiedAt = tinted.TintModifiedAt
        };
    }

    /// Whether `fallback`'s edit is the later: it has a clock that `preferred`
    /// lacks or a strictly later one.
    private static bool Later(SyncTime? preferred, SyncTime? fallback) => fallback is { } other
        && (preferred is not { } own || other.ReferenceSeconds > own.ReferenceSeconds);

    #endregion

    #region Actions - Validation

    /// Throws `UnreadableSyncPayloadException` when a client would not take the split.
    public void Validate() {
        if (CustomTitle is { } title
            && (title.Length == 0 || System.Text.Encoding.UTF8.GetByteCount(title) > SyncedText.SplitTitle.Limit))
            throw new UnreadableSyncPayloadException();
        if (CustomIconSymbol is { } icon && (icon.Length == 0 || System.Text.Encoding.UTF8.GetByteCount(icon) > SyncedText.SplitIcon.Limit
            || EmojiIcon.Parse(icon) is null)) throw new UnreadableSyncPayloadException();
    }

    #endregion
}
