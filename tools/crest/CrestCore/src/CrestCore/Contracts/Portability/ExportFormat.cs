namespace CrestCore.Contracts;

/// A file Crest writes a workspace into: its suggested file name, the uniform
/// type the platform saves it as, and what the person reads while it is
/// written and once it is saved. A format travels as its index in `All`, so
/// `All` is append-only.
public sealed class ExportFormat {
    #region Static Variables

    /// Crest's own browser data, which a later import reads back whole:
    /// Spaces, folders, saved and open tabs, Archive, history and browsing
    /// preferences.
    public static readonly ExportFormat BrowserData = new(name: "browserData", fileName: "Crest Browser Data.json",
        contentType: "public.json", preparingMessage: "Preparing browser data…", savedMessage: "Browser data exported.");

    /// Every Space's pinned and saved tabs and saved folders as a Netscape
    /// bookmark file other browsers import.
    public static readonly ExportFormat Bookmarks = new(name: "bookmarks", fileName: "Crest Bookmarks.html", contentType: "public.html",
        preparingMessage: "Preparing bookmarks…", savedMessage: "Bookmarks exported.");

    public static IReadOnlyList<ExportFormat> All { get; } = [BrowserData, Bookmarks];

    #endregion

    #region Variables

    public string Name { get; }

    /// The name the platform suggests for the file.
    public string FileName { get; }

    /// The uniform type identifier the file is saved as.
    public string ContentType { get; }

    /// What the person reads while the file is written.
    [Localized]
    public string PreparingMessage { get; }

    /// What the person reads once the file is saved.
    [Localized]
    public string SavedMessage { get; }

    #endregion

    #region Constructors

    private ExportFormat(string name, string fileName, string contentType, string preparingMessage, string savedMessage) {
        Name = name;
        FileName = fileName;
        ContentType = contentType;
        PreparingMessage = preparingMessage;
        SavedMessage = savedMessage;
    }

    #endregion

    #region Actions - Lookup

    public static ExportFormat? Named(string? name) => All.FirstOrDefault(format => format.Name == name);

    #endregion
}
