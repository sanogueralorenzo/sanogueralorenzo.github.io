using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One thing that ranks a palette row, which says how many points it adds for
/// what ranking read of the row, the reason it gives the row once it adds
/// enough, and how much it must add before the row may lead the palette. A
/// row's score is the sum of its kind's signals; its reason is the first of
/// them, in its kind's order, that adds enough to name it.
internal sealed class PaletteSignal {
    #region Static Variables

    /// A tab used within the hour adds all of its recency; it fades over a day.
    private static readonly TimeSpan FreshUse = TimeSpan.FromHours(1);
    private static readonly TimeSpan FadedUse = TimeSpan.FromDays(1);

    /// What the person picked before for the same text.
    public static readonly PaletteSignal Learned = new(PaletteReason.Learned, namesAt: 200, leadsAt: null,
        (evidence, _) => (int)evidence.Learned);

    /// How recently the row's tab was used: two hundred within the hour,
    /// none after a day.
    public static readonly PaletteSignal Recency = new(PaletteReason.RecentlyUsed, namesAt: 100, leadsAt: 100,
        (evidence, context) => RecencyPoints(evidence.LastUsed, context.Now));

    /// How often and recently the row's page was visited: sixty for each
    /// doubling of its frecency, at most three hundred.
    public static readonly PaletteSignal Usage = new(PaletteReason.OftenVisited, namesAt: 120, leadsAt: 120,
        (evidence, _) => (int)Math.Min(300, 60 * Math.Log2(1 + evidence.Frecency)));

    /// The row's tab is open, which counts when the person prefers open tabs.
    public static readonly PaletteSignal OpenTab = new(PaletteReason.OpenTab, namesAt: 1, leadsAt: 1,
        (evidence, context) => evidence.IsOpen && context.Preferences.PrefersOpenTabs ? 150 : 0);

    /// The row's tab is pinned or saved.
    public static readonly PaletteSignal Kept = new(PaletteReason.Kept, namesAt: 1, leadsAt: 1, (evidence, _) => evidence.IsKept ? 100 : 0);

    /// How well the text matched the row, which never names a reason itself.
    public static readonly PaletteSignal Match = new(reason: null, namesAt: null, leadsAt: null, (evidence, _) => evidence.Match);

    #endregion

    #region Variables

    /// The reason the signal gives a row, or null for none.
    private readonly PaletteReason? reason;

    /// The points the signal must add to name the row's reason, or null when it never does.
    private readonly int? namesAt;

    /// The points the signal must add before the row may lead, or null when it never lets one.
    private readonly int? leadsAt;

    private readonly Func<PaletteEvidence, PaletteContext, int> points;

    #endregion

    #region Constructors

    private PaletteSignal(PaletteReason? reason, int? namesAt, int? leadsAt, Func<PaletteEvidence, PaletteContext, int> points) {
        this.reason = reason;
        this.namesAt = namesAt;
        this.leadsAt = leadsAt;
        this.points = points;
    }

    #endregion

    #region Actions - Scoring

    /// The points the signal adds for `evidence` in `context`.
    public int Points(PaletteEvidence evidence, PaletteContext context) => points(evidence, context);

    /// The reason the signal names for `evidence`, or null when it adds too
    /// little or names none.
    public PaletteReason? Names(PaletteEvidence evidence, PaletteContext context) =>
        namesAt is { } needed && Points(evidence, context) >= needed ? reason : null;

    /// Whether the signal adds enough for the row to lead the palette.
    public bool Leads(PaletteEvidence evidence, PaletteContext context) => leadsAt is { } needed && Points(evidence, context) >= needed;

    private static int RecencyPoints(DateTimeOffset? used, DateTimeOffset now) {
        if (used is not { } last) return 0;
        var age = now - last;
        if (age <= FreshUse) return 200;
        if (age >= FadedUse) return 0;
        return (int)(200 * (FadedUse - age).TotalMinutes / (FadedUse - FreshUse).TotalMinutes);
    }

    #endregion
}
