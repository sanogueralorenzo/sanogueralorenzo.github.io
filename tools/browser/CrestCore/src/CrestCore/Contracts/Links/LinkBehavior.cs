namespace CrestCore.Contracts;

/// One on-or-off link preference, as a settings switch names it.
public sealed class LinkBehavior {
    #region Static Variables

    /// A link opened in a new tab brings that tab forward.
    public static readonly LinkBehavior FocusesNewTabs = new(name: "focusesNewTabs",
        isOn: preferences => preferences.FocusesNewTabs, setting: (preferences, on) => preferences with { FocusesNewTabs = on });

    /// A window follows a tab it moves to another Space.
    public static readonly LinkBehavior FollowsMovedTabs = new(name: "followsMovedTabs",
        isOn: preferences => preferences.FollowsMovedTabs, setting: (preferences, on) => preferences with { FollowsMovedTabs = on });

    /// A link that leaves a saved tab's site opens in Peek by itself.
    public static readonly LinkBehavior OpensPeekAutomatically = new(name: "opensPeekAutomatically",
        isOn: preferences => preferences.OpensPeekAutomatically,
        setting: (preferences, on) => preferences with { OpensPeekAutomatically = on });

    /// Dragging a link out of a page opens it in Peek.
    public static readonly LinkBehavior DragsLinksToPeek = new(name: "dragsLinksToPeek",
        isOn: preferences => preferences.DragsLinksToPeek, setting: (preferences, on) => preferences with { DragsLinksToPeek = on });

    /// A Quick Window remembers the Space it last opened each site in.
    public static readonly LinkBehavior RemembersSpaceBySite = new(name: "remembersSpaceBySite",
        isOn: preferences => preferences.RemembersSpaceBySite,
        setting: (preferences, on) => preferences with { RemembersSpaceBySite = on });

    public static IReadOnlyList<LinkBehavior> All { get; } =
        [FocusesNewTabs, FollowsMovedTabs, OpensPeekAutomatically, DragsLinksToPeek, RemembersSpaceBySite];

    #endregion

    #region Variables

    public string Name { get; }

    private readonly Func<LinkPreferences, bool> isOn;
    private readonly Func<LinkPreferences, bool, LinkPreferences> setting;

    #endregion

    #region Constructors

    private LinkBehavior(string name, Func<LinkPreferences, bool> isOn, Func<LinkPreferences, bool, LinkPreferences> setting) {
        Name = name;
        this.isOn = isOn;
        this.setting = setting;
    }

    #endregion

    #region Actions - Preferences

    public static LinkBehavior? Named(string? name) => All.FirstOrDefault(behavior => behavior.Name == name);

    /// Whether `preferences` turn the behavior on.
    public bool IsOn(LinkPreferences preferences) => isOn(preferences);

    /// `preferences` with the behavior turned on or off.
    public LinkPreferences Setting(LinkPreferences preferences, bool on) => setting(preferences, on);

    #endregion
}
