using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

/// What deciding the palette's best match reads for typed text: the query,
/// the address the field completes, the row the person picked before for the
/// same text, every row ranked, and whether the field may complete now.
internal sealed record PaletteLeading(PaletteQuery Query, AddressMatch? Completion, PaletteDestination? Habit,
    IReadOnlyList<PaletteCandidate> Ranked, bool Completes);

#endregion

/// One way a row comes to lead the palette as its best match, so Return runs
/// it. The rules are asked in order and the first that names a row leads:
/// a calculation, the address the field completes, what the person picked at
/// least twice for this text, then a strongly used place whose title or
/// address starts with the text. While the field may not complete, as after
/// the person deleted a completion, only a calculation leads, so Return runs
/// what they typed.
internal sealed class PaletteLeadRule {
    #region Static Variables

    /// Arithmetic the text spells, whose answer Return copies.
    public static readonly PaletteLeadRule Calculation = new((context, leading) =>
        context.Preferences.Offers(PaletteSource.Calculator) && Domain.Calculation.Of(leading.Query.Text) is { } calculation
            ? new(PaletteRow.Of(PaletteRowKind.Calculation, calculation.Answer, $"{calculation.Expression} ="), PaletteSource.Calculator,
                int.MaxValue, Place: null, MayLead: true)
            : null);

    /// The address the field completes, as its open tab when the person
    /// prefers open tabs and one shows it.
    public static readonly PaletteLeadRule Completion = new((context, leading) => {
        if (!leading.Completes || leading.Completion is not { } completion) return null;
        string? place = PaletteMemory.Place(completion.Opens);
        if (context.Preferences.PrefersOpenTabs
            && leading.Ranked.FirstOrDefault(entry => entry.Place == place && entry.Row.TabId is not null) is { } open)
            return open with { Row = open.Row with { Reason = PaletteReason.Completion } };
        string host = completion.Text.Contains("://", StringComparison.Ordinal) ? completion.Text : completion.Text.TrimEnd('/');
        return new(PaletteRow.Of(PaletteRowKind.OpenAddress, $"Open {host}", completion.Opens, address: completion.Opens,
            reason: PaletteReason.Completion), PaletteSource.History, int.MaxValue, place, MayLead: true);
    });

    /// The row the person picked at least twice for exactly this text.
    public static readonly PaletteLeadRule Habit = new((context, leading) =>
        leading.Completes && leading.Habit is { } habit && leading.Ranked.FirstOrDefault(entry => context.Destination(entry.Row) == habit)
            is { } learned
            ? learned with { Row = learned.Row with { Reason = PaletteReason.Learned } }
            : null);

    /// The strongest row that may lead, once two letters are typed and the
    /// person shows a Top Hit.
    public static readonly PaletteLeadRule StrongPlace = new((context, leading) =>
        leading.Completes && context.Preferences.ShowsTopHit && leading.Query.Text.Length >= 2
            ? leading.Ranked.Where(entry => entry.MayLead).MaxBy(entry => entry.Score)
            : null);

    /// The rules, in the order the palette asks them.
    public static IReadOnlyList<PaletteLeadRule> All { get; } = [Calculation, Completion, Habit, StrongPlace];

    #endregion

    #region Variables

    private readonly Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads;

    #endregion

    #region Constructors

    private PaletteLeadRule(Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads) => this.leads = leads;

    #endregion

    #region Actions - Leading

    /// The row this rule makes lead, or null when it names none.
    public PaletteCandidate? Leads(PaletteContext context, PaletteLeading leading) => leads(context, leading);

    /// The row the first rule that names one makes lead, or null when none does.
    public static PaletteCandidate? First(PaletteContext context, PaletteLeading leading) =>
        All.Select(rule => rule.Leads(context, leading)).FirstOrDefault(candidate => candidate is not null);

    #endregion
}
