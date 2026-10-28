namespace CrestCore.Contracts;

/// Where one download record stands. Live phases belong to a transfer that an
/// engine or a pending prompt still owns; a blocked automatic download waits
/// for the person to retry it; finished, canceled and failed records are final.
///
/// A phase travels as its index in `All`, so `All` is append-only.
public sealed class DownloadPhase {
    #region Variables

    public static readonly DownloadPhase Preparing = new(name: "preparing", title: "Preparing…", symbol: null,
        primaryAction: DownloadRowAction.Cancel, isLive: true);
    public static readonly DownloadPhase AwaitingApproval = new(name: "awaitingApproval", title: "Waiting for approval…",
        symbol: "exclamationmark.shield.fill", primaryAction: DownloadRowAction.Cancel, isLive: true, awaitsDecision: true);
    public static readonly DownloadPhase Downloading = new(name: "downloading", title: "Downloading…", symbol: null,
        primaryAction: DownloadRowAction.Cancel, isLive: true, isTransferring: true, allowsResume: true);
    public static readonly DownloadPhase Finished = new(name: "finished", title: "Completed", symbol: null,
        primaryAction: DownloadRowAction.Open, isComplete: true,
        titleComment: "Status of a download whose file is saved.");
    public static readonly DownloadPhase BlockedAutomaticDownload = new(name: "blockedAutomaticDownload",
        title: "Automatic download blocked. Use Allow Download to retry, or change Automatic Downloads in this site’s permissions.",
        symbol: "arrow.down.circle.fill", primaryAction: DownloadRowAction.Retry, needsAttention: true, canRetry: true,
        awaitsDecision: true);
    public static readonly DownloadPhase Canceled = new(name: "canceled", title: null, symbol: "xmark.circle.fill",
        primaryAction: DownloadRowAction.Remove);
    public static readonly DownloadPhase Failed = new(name: "failed", title: null, symbol: "exclamationmark.triangle.fill",
        primaryAction: DownloadRowAction.Remove, needsAttention: true, allowsResume: true);

    public static IReadOnlyList<DownloadPhase> All { get; } =
        [Preparing, AwaitingApproval, Downloading, Finished, BlockedAutomaticDownload, Canceled, Failed];

    public string Name { get; }

    /// The status a row shows for the phase. A canceled or failed record shows
    /// its own message instead.
    [Localized]
    public string? Title { get; }

    public string? TitleComment { get; }

    /// The SF Symbol a row shows for the phase. Without one, a row shows the
    /// transfer's progress while it is live and the file's icon once it is not.
    public string? Symbol { get; }

    /// What the row offers the person in this phase.
    public DownloadRowAction PrimaryAction { get; }

    /// A transfer an engine or a pending prompt still owns. Only a live record
    /// accepts transfer events and cancellation, and it never expires.
    public bool IsLive { get; }

    /// Bytes are arriving, so a rate and a time remaining mean something.
    public bool IsTransferring { get; }

    /// The file is saved in full at the record's destination.
    public bool IsComplete { get; }

    /// The download failed or is blocked, so the person should look.
    public bool NeedsAttention { get; }

    /// The download goes on only once the person decides: approving it, or
    /// allowing an automatic download that was blocked.
    public bool AwaitsDecision { get; }

    /// Retrying starts the same record again from nothing.
    public bool CanRetry { get; }

    /// The engine may offer to resume a record in this phase: a transfer it
    /// paused, or a failed one it can recover.
    public bool AllowsResume { get; }

    /// A live transfer can fail, and so can a record whose retry can no longer
    /// be replayed.
    public bool CanFail => IsLive || CanRetry;

    #endregion

    #region Constructors

    private DownloadPhase(string name, string? title, string? symbol, DownloadRowAction primaryAction, bool isLive = false,
        bool isTransferring = false, bool isComplete = false, bool needsAttention = false, bool awaitsDecision = false,
        bool canRetry = false, bool allowsResume = false, string? titleComment = null) {
        Name = name;
        Title = title;
        TitleComment = titleComment;
        Symbol = symbol;
        PrimaryAction = primaryAction;
        IsLive = isLive;
        IsTransferring = isTransferring;
        IsComplete = isComplete;
        NeedsAttention = needsAttention;
        AwaitsDecision = awaitsDecision;
        CanRetry = canRetry;
        AllowsResume = allowsResume;
    }

    #endregion

    #region Actions - Lookup

    public static DownloadPhase? Named(string? name) => All.FirstOrDefault(phase => phase.Name == name);

    #endregion
}
