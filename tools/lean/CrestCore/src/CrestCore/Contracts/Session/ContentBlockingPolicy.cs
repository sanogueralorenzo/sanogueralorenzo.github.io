namespace CrestCore.Contracts;

/// Whether a Space enables its engine's content blocker. WebKit runs bundled
/// uBlock Origin Lite; the stored names and wire indices remain stable.
public sealed class ContentBlockingPolicy {
    #region Static Variables

    public static readonly ContentBlockingPolicy Balanced = new(name: "balanced", title: "On",
        switchTitle: "Turn Off Content Blocking in This Space", blocksContent: true);
    public static readonly ContentBlockingPolicy Off = new(name: "off", title: "Off",
        switchTitle: "Turn On Content Blocking in This Space", blocksContent: false);
    public static IReadOnlyList<ContentBlockingPolicy> All { get; } = [Balanced, Off];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized]
    public string Title { get; }
    [Localized]
    public string SwitchTitle { get; }
    public bool BlocksContent { get; }

    #endregion

    #region Constructors

    private ContentBlockingPolicy(string name, string title, string switchTitle, bool blocksContent) {
        Name = name;
        Title = title;
        SwitchTitle = switchTitle;
        BlocksContent = blocksContent;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBlockingPolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion
}
