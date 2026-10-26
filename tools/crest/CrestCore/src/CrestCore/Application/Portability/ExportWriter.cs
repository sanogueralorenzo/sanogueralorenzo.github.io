using CrestCore.Contracts;

namespace CrestCore.Application;

/// How the core writes each file an export makes, for the `ExportFormat` the
/// platform names.
internal sealed class ExportWriter {
    #region Static Variables

    public static readonly ExportWriter BrowserData = new(ExportFormat.BrowserData,
        (spaces, now) => BrowserDataFile.Write(spaces.Select(BrowserDataSpace.From), now));
    public static readonly ExportWriter Bookmarks = new(ExportFormat.Bookmarks, BookmarkFile.Write);

    public static IReadOnlyList<ExportWriter> All { get; } = [BrowserData, Bookmarks];

    #endregion

    #region Variables

    public ExportFormat Format { get; }

    private readonly Func<IReadOnlyList<SpaceState>, DateTimeOffset, byte[]> write;

    #endregion

    #region Constructors

    private ExportWriter(ExportFormat format, Func<IReadOnlyList<SpaceState>, DateTimeOffset, byte[]> write) {
        Format = format;
        this.write = write;
    }

    #endregion

    #region Actions - Writing

    public static ExportWriter Of(ExportFormat format) => All.First(writer => writer.Format == format);

    /// The file of `session`'s Spaces, exported at `now`.
    public ExportedDocument Write(SessionState session, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(session);
        return new(write(session.Spaces, now), Format);
    }

    #endregion
}
