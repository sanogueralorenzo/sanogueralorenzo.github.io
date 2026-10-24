using CrestCore.Contracts;

using static CrestCore.Application.PropertyListValue;

namespace CrestCore.Application;

/// Safari's `Bookmarks.plist`: a tree of leaves, each a link, and lists, each
/// a folder, below its top level.
internal static class SafariBookmarks {
    #region Static Variables

    private const string LeafType = "WebBookmarkTypeLeaf";

    /// The names Safari shows for the lists it keeps at the top, which its
    /// file spells another way.
    private static readonly IReadOnlyDictionary<string, string> ShownTitles = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["BookmarksBar"] = "Favorites",
        ["BookmarksMenu"] = "Bookmarks Menu",
        ["com.apple.ReadingList"] = "Reading List"
    };

    #endregion

    #region Actions - Reading

    /// Adds the bookmarks the file holds to `draft`. A link without a usable
    /// time is dated `importedAt`. Throws `Rejected` with
    /// `BookmarksUnrecognized` for a file that is not Safari's bookmarks.
    public static void Read(byte[] contents, DateTimeOffset importedAt, BookmarkDraft draft) {
        ArgumentNullException.ThrowIfNull(draft);
        var root = Dictionary(PropertyList.Read(contents));
        var children = Array(Member(root, "Children")) ?? throw new Rejected(new BookmarksUnrecognized());
        Append(children, parent: null, depth: 0, draft, importedAt);
    }

    private static void Append(IReadOnlyList<object> children, Guid? parent, int depth, BookmarkDraft draft, DateTimeOffset importedAt) {
        foreach (var child in children.Select(Dictionary).OfType<IReadOnlyDictionary<string, object>>()) {
            if (Text(Member(child, "WebBookmarkType")) == LeafType && Text(Member(child, "URLString")) is { } url) {
                string title = Text(Member(Dictionary(Member(child, "URIDictionary")), "title")) ?? Text(Member(child, "Title")) ?? "";
                var added = child.ContainsKey("DateAdded") ? Member(child, "DateAdded") : Member(child, "DateVisited");
                draft.AppendBookmark(title, url, parent, Added(added) ?? importedAt);
                continue;
            }
            if (Array(Member(child, "Children")) is not { } nested) continue;
            string? name = Text(Member(child, "Title"));
            if (depth == 0 && name is not null && ShownTitles.TryGetValue(name, out var shown)) name = shown;
            if (draft.AppendFolder(name, parent, depth) is { } folder)
                Append(nested, folder, depth + 1, draft, importedAt);
        }
    }

    /// A time Safari keeps as a date, or as a number or a string in whichever
    /// unit its size suggests, when it is a positive, finite time.
    private static DateTimeOffset? Added(object? value) {
        if (value is PropertyListDate date) return ImportDate.FromReferenceSeconds(date.ReferenceSeconds);
        double? raw = Number(value) ?? (Text(value) is { } text ? ImportJson.SpelledNumber(text) : null);
        return raw is { } number && double.IsFinite(number) && number > 0 ? ImportDate.FromAnyUnit(number) : null;
    }

    #endregion
}
