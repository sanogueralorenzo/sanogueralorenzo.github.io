namespace CrestCore.Contracts;

/// Where iCloud sync stands, and how the settings show it.
///
/// A phase travels as its index in `All`, so `All` is append-only.
public sealed class CloudSyncPhase {
    #region Variables

    public static readonly CloudSyncPhase Disabled = new(name: "disabled", isRetryable: false, title: "Off", symbol: "icloud.slash",
        tint: null, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase Checking = new(name: "checking", isRetryable: false, title: "Checking iCloud",
        symbol: "arrow.triangle.2.circlepath.icloud", tint: SystemTint.Blue, keepsCloudOutOfReach: true);
    /// Sync works, and this device's journal holds records that have not
    /// reached iCloud yet.
    public static readonly CloudSyncPhase WaitingToUpload = new(name: "waitingToUpload", isRetryable: false, title: "Waiting to upload",
        symbol: "icloud.and.arrow.up", tint: SystemTint.Blue, keepsCloudOutOfReach: false);
    /// Sync works, and nothing on this device waits to upload.
    public static readonly CloudSyncPhase Ready = new(name: "ready", isRetryable: false, title: "Up to date", symbol: "checkmark.icloud.fill",
        tint: SystemTint.Green, keepsCloudOutOfReach: false, whileUploadsWait: WaitingToUpload);
    public static readonly CloudSyncPhase Syncing = new(name: "syncing", isRetryable: false, title: "Syncing",
        symbol: "arrow.triangle.2.circlepath.icloud", tint: SystemTint.Blue, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase NeedsReconciliation = new(name: "needsReconciliation", isRetryable: false,
        title: "Choose which copy to keep", symbol: "exclamationmark.icloud.fill", tint: SystemTint.Orange, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase WaitingForAccount = new(name: "waitingForAccount", isRetryable: true, title: "Waiting for iCloud",
        symbol: "person.crop.circle.badge.exclamationmark", tint: SystemTint.Orange, keepsCloudOutOfReach: true);
    public static readonly CloudSyncPhase Failed = new(name: "failed", isRetryable: true, title: "Needs attention",
        symbol: "xmark.icloud.fill", tint: SystemTint.Red, keepsCloudOutOfReach: true);

    public static IReadOnlyList<CloudSyncPhase> All { get; } =
        [Disabled, Checking, Ready, Syncing, NeedsReconciliation, WaitingForAccount, Failed, WaitingToUpload];

    public string Name { get; }

    /// Whether trying the same thing again could reach a different answer. A
    /// missing account and a failed launch both heal on their own once iCloud
    /// is reachable; everything else is working, in progress, or waiting on a
    /// decision only somebody using Crest can make.
    public bool IsRetryable { get; }

    /// What the settings call the phase.
    [Localized]
    public string Title { get; }

    /// The SF Symbol the settings show beside the phase.
    public string Symbol { get; }

    /// The color the settings tint the phase with, or null for the secondary
    /// color of a phase that needs nothing.
    public SystemTint? Tint { get; }

    /// Whether iCloud's content is out of this device's reach: the check for
    /// it has not answered, no account is signed in, or sync failed.
    public bool KeepsCloudOutOfReach { get; }

    /// The phase this one reads as while records wait to upload, when it
    /// gives way to them: a sync that has nothing left to do is not up to
    /// date while this device's changes have not left it.
    internal CloudSyncPhase? WhileUploadsWait { get; }

    #endregion

    #region Constructors

    private CloudSyncPhase(string name, bool isRetryable, string title, string symbol, SystemTint? tint, bool keepsCloudOutOfReach,
        CloudSyncPhase? whileUploadsWait = null) {
        Name = name;
        IsRetryable = isRetryable;
        Title = title;
        Symbol = symbol;
        Tint = tint;
        KeepsCloudOutOfReach = keepsCloudOutOfReach;
        WhileUploadsWait = whileUploadsWait;
    }

    #endregion

    #region Actions - Presenting

    /// The phase the settings show while `pendingUploads` records wait to
    /// upload.
    internal CloudSyncPhase Showing(int pendingUploads) => pendingUploads > 0 && WhileUploadsWait is { } waiting ? waiting : this;

    #endregion
}
