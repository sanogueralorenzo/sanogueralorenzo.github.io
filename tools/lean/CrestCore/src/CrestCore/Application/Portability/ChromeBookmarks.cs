using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A Chromium profile's `Bookmarks` JSON, or the `AccountBookmarks` a
/// signed-in profile keeps beside it: its roots, the bookmarks bar, other and
/// mobile bookmarks first, each a folder of links and folders, with times in
/// microseconds since 1601.
internal static class ChromeBookmarks {
    #region Static Variables

    /// The roots Chrome shows, in the order it shows them; others follow in
    /// the order of their names.
    private static readonly string[] PreferredRoots = ["bookmark_bar", "other", "synced"];
    /// The roots a browser keeps for what the person deleted, as Vivaldi's
    /// trash, which no import brings.
    private static readonly string[] DeletedRoots = ["trash"];

    private const string LinkType = "url";
    private const string FolderType = "folder";

    #endregion

    #region Actions - Reading

    /// Adds the bookmarks the file holds to `draft`. A link without a usable
    /// time is dated `importedAt`. Throws `Rejected` with
    /// `BookmarksUnrecognized` for a file that is not Chrome's bookmarks.
    public static void Read(byte[] contents, DateTimeOffset importedAt, BookmarkDraft draft) {
        ArgumentNullException.ThrowIfNull(draft);
        using var document = ImportJson.Parse(contents) ?? throw new Rejected(new BookmarksUnrecognized());
        var roots = ImportJson.Object(ImportJson.Member(ImportJson.Object(document.RootElement), "roots"))
            ?? throw new Rejected(new BookmarksUnrecognized());
        var remaining = ImportJson.Members(roots).Select(member => member.Name)
            .Where(name => !PreferredRoots.Contains(name) && !DeletedRoots.Contains(name)).Order(StringComparer.Ordinal);
        foreach (string key in PreferredRoots.Concat(remaining))
            if (ImportJson.Object(ImportJson.Member(roots, key)) is { } node && HoldsLinks(node))
                Append(node, parent: null, depth: 0, draft, importedAt);
    }

    /// Whether `node` is a link or holds one at any depth, so a root the
    /// person never filled makes no folder. The document nests no deeper than
    /// its parse allows.
    private static bool HoldsLinks(JsonElement node) =>
        ImportJson.Text(ImportJson.Member(node, "type")) == LinkType
        || (ImportJson.Array(ImportJson.Member(node, "children")) ?? [])
            .Any(child => child.ValueKind == JsonValueKind.Object && HoldsLinks(child));

    private static void Append(JsonElement? node, Guid? parent, int depth, BookmarkDraft draft, DateTimeOffset importedAt) {
        string? type = ImportJson.Text(ImportJson.Member(node, "type"));
        if (type == LinkType && ImportJson.Text(ImportJson.Member(node, "url")) is { } url) {
            draft.AppendBookmark(ImportJson.Text(ImportJson.Member(node, "name")) ?? "", url, parent,
                Added(ImportJson.Member(node, "date_added")) ?? importedAt);
            return;
        }
        var childrenMember = ImportJson.Member(node, "children");
        if ((type != FolderType && childrenMember is null) || ImportJson.Array(childrenMember) is not { } children) return;
        if (draft.AppendFolder(ImportJson.Text(ImportJson.Member(node, "name")), parent, depth) is not { } folder) return;
        foreach (var child in children.Where(child => child.ValueKind == JsonValueKind.Object))
            Append(child, folder, depth + 1, draft, importedAt);
    }

    /// A time Chrome spells as a number or a string of microseconds since
    /// 1601, when it is a positive, finite time.
    private static DateTimeOffset? Added(JsonElement? value) {
        double? raw = ImportJson.Number(value) ?? (ImportJson.Text(value) is { } text ? ImportJson.SpelledNumber(text) : null);
        return raw is { } number && double.IsFinite(number) && number > 0 ? ImportDate.FromWindowsMicroseconds(number) : null;
    }

    #endregion
}
