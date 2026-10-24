namespace CrestCore.Domain;

/// How well one typed term matches a row's text: somewhere inside a word, at
/// the start of a word, or at the start of the text. A better match scores
/// more points.
public sealed class TextMatch {
    #region Static Variables

    public static readonly TextMatch Inside = new(points: 300);
    public static readonly TextMatch WordStart = new(points: 700);
    public static readonly TextMatch TextStart = new(points: 1_000);

    #endregion

    #region Variables

    public int Points { get; }

    #endregion

    #region Constructors

    private TextMatch(int points) => Points = points;

    #endregion

    #region Actions - Comparison

    /// The better of two matches.
    public TextMatch Better(TextMatch other) => other.Points > Points ? other : this;

    #endregion
}
