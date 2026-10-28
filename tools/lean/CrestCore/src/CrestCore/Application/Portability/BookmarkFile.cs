using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The Netscape bookmark file an export writes, which every browser imports:
/// each Space as a folder marked as a Crest Space, holding its pinned and
/// saved tabs outside folders and then its saved folders with their saved
/// tabs. Open tabs, the archive and history stay out of it.
internal static class BookmarkFile {
    #region Static Variables

    /// The largest file an export writes.
    public const int MaximumBytes = 50 * 1024 * 1024;

    private const string Indent = "    ";

    #endregion

    #region Actions - Writing

    /// The file of `spaces`, exported at `exportedAt`. Throws `Rejected` with
    /// `BookmarksTooLarge` when it would be larger than an import reads.
    public static byte[] Write(IEnumerable<SpaceState> spaces, DateTimeOffset exportedAt) {
        var output = new StringBuilder();
        output.Append("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n")
            .Append("<!-- This is an automatically generated file. -->\n")
            .Append("<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n")
            .Append("<TITLE>Crest Bookmarks</TITLE>\n")
            .Append("<H1>Crest Bookmarks</H1>\n")
            .Append("<DL><p>\n");
        foreach (var space in spaces) WriteSpace(output, space, exportedAt, depth: 1);
        output.Append("</DL><p>\n");
        var contents = Encoding.UTF8.GetBytes(output.ToString());
        return contents.Length > MaximumBytes ? throw new Rejected(new BookmarksTooLarge()) : contents;
    }

    private static void WriteSpace(StringBuilder output, SpaceState space, DateTimeOffset exportedAt, int depth) {
        string prefix = string.Concat(Enumerable.Repeat(Indent, depth));
        output.Append($"{prefix}<DT><H3 ADD_DATE=\"{UnixSeconds(exportedAt)}\" CREST_SPACE=\"true\">")
            .Append(Text(space.Settings.Name)).Append("</H3>\n")
            .Append($"{prefix}<DL><p>\n");
        WriteLinks(output, space.Tabs.Where(tab => tab.Placement.IsDurable && tab.FolderId is null), depth + 1);
        foreach (var folder in space.Folders.Where(folder => folder.ParentId is null && folder.Location == TabPlacement.Saved))
            WriteFolder(output, space, folder, depth + 1);
        output.Append($"{prefix}</DL><p>\n");
    }

    private static void WriteFolder(StringBuilder output, SpaceState space, FolderState folder, int depth) {
        string prefix = string.Concat(Enumerable.Repeat(Indent, depth));
        output.Append($"{prefix}<DT><H3>").Append(Text(folder.Title)).Append("</H3>\n").Append($"{prefix}<DL><p>\n");
        WriteLinks(output, space.Tabs.Where(tab => tab.Placement == TabPlacement.Saved && tab.FolderId == folder.Id), depth + 1);
        foreach (var child in space.Folders.Where(child => child.ParentId == folder.Id)) WriteFolder(output, space, child, depth + 1);
        output.Append($"{prefix}</DL><p>\n");
    }

    /// Each tab's saved address, or the page it shows, as a link.
    private static void WriteLinks(StringBuilder output, IEnumerable<TabState> tabs, int depth) {
        string prefix = string.Concat(Enumerable.Repeat(Indent, depth));
        foreach (var tab in tabs) {
            if (ImportAddress.Read(tab.SavedUrl ?? tab.Url) is not { } address) continue;
            output.Append($"{prefix}<DT><A HREF=\"{Attribute(address.Spelling)}\" ADD_DATE=\"{UnixSeconds(tab.LastActivatedAt)}\">")
                .Append(Text(tab.Title)).Append("</A>\n");
        }
    }

    /// Whole seconds since 1970, or zero for a time before it.
    private static long UnixSeconds(DateTimeOffset date) {
        double seconds = ImportDate.UnixSeconds(date);
        return double.IsFinite(seconds) && seconds > 0 ? (long)Math.Min(Math.Floor(seconds), long.MaxValue) : 0;
    }

    private static string Text(string source) =>
        source.Replace("&", "&amp;", StringComparison.Ordinal).Replace("<", "&lt;", StringComparison.Ordinal)
            .Replace(">", "&gt;", StringComparison.Ordinal).Replace("\"", "&quot;", StringComparison.Ordinal);

    private static string Attribute(string source) => Text(source).Replace("'", "&#39;", StringComparison.Ordinal);

    #endregion
}
