namespace CrestCore.Contracts;

/// What a crest's custom figure is drawn from.
public sealed class CrestChargeKind {
    #region Types

    /// A figure of each kind is made and drawn from different parts, so the code that makes or draws one switches over the kind.
    public enum Kinds { Heraldic, System, Emoji, Monogram, None }

    #endregion

    #region Static Variables

    /// The most letters a monogram figure shows.
    private const int MaximumMonogramLength = 2;

    public static readonly CrestChargeKind Heraldic = new(Kinds.Heraldic, "heraldic", "Heraldry", true, true, normalize: charge => charge);
    public static readonly CrestChargeKind System = new(Kinds.System, "system", "SF Symbol", true, true, normalize: charge =>
        Trimmed(charge) is { Length: > 0 } text ? charge with { Text = text } : Undrawn());
    public static readonly CrestChargeKind Emoji = new(Kinds.Emoji, "emoji", "Emoji", false, false, normalize: charge =>
        string.IsNullOrEmpty(charge.Text) ? Undrawn()
            : charge with { Text = new global::System.Globalization.StringInfo(charge.Text).SubstringByTextElements(0, 1) });
    public static readonly CrestChargeKind Monogram = new(Kinds.Monogram, "monogram", "Monogram", true, true, normalize: charge =>
        Trimmed(charge) is { Length: > 0 } text
            ? charge with { Text = FirstTextElements(text.ToUpperInvariant(), MaximumMonogramLength).ToUpperInvariant() }
            : Undrawn());
    public static readonly CrestChargeKind None = new(Kinds.None, "none", "None", false, false, normalize: charge => charge);

    public static IReadOnlyList<CrestChargeKind> All { get; } = [Heraldic, System, Emoji, Monogram, None];

    #endregion

    #region Variables

    public Kinds Kind { get; }
    public string Name { get; }

    /// The choice's name where a person picks it.
    [Localized]
    public string Title { get; }

    /// Whether the figure is painted in the crest's emblem color; an emoji keeps its own colors.
    public bool IsTinted { get; }

    /// Whether the figure is drawn in a stroke weight a person can choose.
    public bool TakesWeight { get; }

    /// A figure of this kind as the renderer draws it.
    private readonly Func<CrestCharge, CrestCharge> normalize;

    #endregion

    #region Constructors

    private CrestChargeKind(Kinds kind, string name, string title, bool isTinted, bool takesWeight,
        Func<CrestCharge, CrestCharge> normalize) {
        Kind = kind;
        Name = name;
        Title = title;
        IsTinted = isTinted;
        TakesWeight = takesWeight;
        this.normalize = normalize;
    }

    #endregion

    #region Actions - Lookup

    public static CrestChargeKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion

    #region Actions - Figures

    /// `charge`, a figure of this kind, as the renderer draws it: names and
    /// letters trimmed, one emoji, a monogram of at most two capitals, and
    /// nothing drawn in place of an empty one.
    public CrestCharge Normalized(CrestCharge charge) => normalize(charge);

    /// No figure, drawn in place of an empty one.
    private static CrestCharge Undrawn() => new(None);

    private static string Trimmed(CrestCharge charge) => charge.Text?.Trim() ?? "";

    private static string FirstTextElements(string text, int count) {
        var elements = new global::System.Globalization.StringInfo(text);
        return elements.LengthInTextElements <= count ? text : elements.SubstringByTextElements(0, count);
    }

    #endregion
}
