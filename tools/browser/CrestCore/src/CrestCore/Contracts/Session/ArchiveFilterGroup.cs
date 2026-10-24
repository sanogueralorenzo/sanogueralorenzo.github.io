namespace CrestCore.Contracts;

/// A filter of a Space's archive list, which shows the tabs archived for the
/// reasons that name it. `All` is the order the list offers them in.
public sealed class ArchiveFilterGroup {
    #region Variables

    public static readonly ArchiveFilterGroup Closed = new(name: "closed", title: "Closed", symbol: "xmark.circle.fill");
    public static readonly ArchiveFilterGroup Automatic = new(name: "automatic", title: "Automatically Cleaned", symbol: "archivebox.fill");
    public static readonly ArchiveFilterGroup Synced = new(name: "synced", title: "Synced from Another Device",
        symbol: "icloud.and.arrow.down.fill");
    public static readonly ArchiveFilterGroup QuickWindow = new(name: "quickWindow", title: "Quick Windows", symbol: "timer");

    public static IReadOnlyList<ArchiveFilterGroup> All { get; } = [Closed, Automatic, Synced, QuickWindow];

    public string Name { get; }

    /// What the filter menu calls the group.
    [Localized]
    public string Title { get; }

    /// The SF Symbol beside the group's name.
    public string Symbol { get; }

    #endregion

    #region Constructors

    private ArchiveFilterGroup(string name, string title, string symbol) {
        Name = name;
        Title = title;
        Symbol = symbol;
    }

    #endregion

    #region Actions - Lookup

    public static ArchiveFilterGroup? Named(string? name) => All.FirstOrDefault(group => group.Name == name);

    #endregion
}
