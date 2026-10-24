namespace CrestCore.Application;

/// How a browser built on Chromium numbers the commands of its session file:
/// as Chromium does, or as Vivaldi does, which keeps records of its own at 21
/// and 22 and moves each of Chromium's from 21 on two places up. The markers
/// at the top of the range keep their numbers.
internal sealed class ChromiumSessionDialect {
    #region Static Variables

    public static readonly ChromiumSessionDialect Chromium = new(inserted: []);
    public static readonly ChromiumSessionDialect Vivaldi = new(inserted: [21, 22]);

    public static IReadOnlyList<ChromiumSessionDialect> All { get; } = [Chromium, Vivaldi];

    /// The first of the markers no browser renumbers, such as Chromium's
    /// initial-state marker at 255 and Opera's at 252.
    private const byte FirstMarker = 252;

    #endregion

    #region Variables

    /// The commands the browser added of its own, in order, before which
    /// Chromium's keep their numbers.
    private readonly byte[] inserted;

    #endregion

    #region Constructors

    private ChromiumSessionDialect(byte[] inserted) => this.inserted = inserted;

    #endregion

    #region Actions - Commands

    /// The Chromium command the browser wrote as `written`, or null for one
    /// of the browser's own.
    public byte? Command(byte written) {
        if (written >= FirstMarker) return written;
        if (inserted.Contains(written)) return null;
        int moved = inserted.Count(added => added < written);
        return (byte)(written - moved);
    }

    #endregion
}
