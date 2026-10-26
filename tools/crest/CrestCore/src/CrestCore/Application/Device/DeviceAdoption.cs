namespace CrestCore.Application;

/// Something the device store carried once from what an installed release
/// kept in its defaults. The store records each one it has done by `Marker`,
/// so a later launch never carries the same thing again.
internal sealed class DeviceAdoption {
    #region Static Variables

    public static readonly DeviceAdoption WindowRecords = new(marker: "window-records", olderBuildsRead: true);
    public static readonly DeviceAdoption SitePermissions = new(marker: "site-permissions", olderBuildsRead: false);
    public static readonly DeviceAdoption Shortcuts = new(marker: "shortcuts", olderBuildsRead: false);
    public static readonly DeviceAdoption LinkPreferences = new(marker: "link-preferences", olderBuildsRead: false);
    /// The cloud transport's state, which the transport kept in a file of its own.
    public static readonly DeviceAdoption CloudTransport = new(marker: "cloud-transport", olderBuildsRead: false);
    public static readonly DeviceAdoption SetupDraft = new(marker: "setup-draft", olderBuildsRead: false);
    public static readonly DeviceAdoption SetupCompletion = new(marker: "setup-completion", olderBuildsRead: false);
    /// The windows the Chromium composition kept open for its next launch,
    /// which it listed in its defaults.
    public static readonly DeviceAdoption OpenWindows = new(marker: "open-windows", olderBuildsRead: false);

    public static IReadOnlyList<DeviceAdoption> All { get; } =
        [WindowRecords, SitePermissions, Shortcuts, LinkPreferences, CloudTransport, SetupDraft, SetupCompletion, OpenWindows];

    #endregion

    #region Variables

    /// The name the store records.
    public string Marker { get; }

    /// A build from before the other adoptions reads this one's marker, and
    /// rewrites that build's marker table without any it does not know.
    public bool OlderBuildsRead { get; }

    #endregion

    #region Constructors

    private DeviceAdoption(string marker, bool olderBuildsRead) {
        Marker = marker;
        OlderBuildsRead = olderBuildsRead;
    }

    #endregion

    #region Actions - Lookup

    public static DeviceAdoption? Marked(string? marker) => All.FirstOrDefault(adoption => adoption.Marker == marker);

    #endregion
}
