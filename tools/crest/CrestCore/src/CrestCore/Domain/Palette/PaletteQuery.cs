using System.Text;

namespace CrestCore.Domain;

/// What a person typed into the palette, trimmed and folded once into its
/// whitespace-separated terms, so every candidate is matched against the same
/// folded text. Folding lowers case, and treats a final sigma as a sigma.
public sealed class PaletteQuery {
    #region Static Variables

    /// What a term matched in a row's detail scores less than the same match
    /// in its title.
    private const int DetailPenalty = 150;
    /// A word typed as the initials of a title's words.
    private const int InitialsPoints = 250;
    /// A word whose letters appear in a title in order.
    private const int SubsequencePoints = 150;
    private static readonly Rune FinalSigma = new('ς');
    private static readonly Rune Sigma = new('σ');

    #endregion

    #region Variables

    /// The text as typed, trimmed.
    public string Text { get; }

    /// Nothing but whitespace was typed.
    public bool IsEmpty => terms.Length == 0;

    private readonly Rune[][] terms;

    #endregion

    #region Constructors

    public PaletteQuery(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        Text = typed.Trim();
        List<Rune[]> found = [];
        List<Rune> current = [];
        foreach (var rune in Text.EnumerateRunes()) {
            if (IsWhitespace(rune)) {
                if (current.Count > 0) found.Add([.. current]);
                current.Clear();
                continue;
            }
            current.Add(Folded(rune));
        }
        if (current.Count > 0) found.Add([.. current]);
        terms = [.. found];
    }

    #endregion

    #region Actions - Scoring

    /// How well every term matches `title`, or else `detail` for less, as the
    /// average points of each term's best match; null when a term matches
    /// neither or nothing was typed.
    public int? Score(string title, string detail = "") {
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(detail);
        if (IsEmpty) return null;
        int total = 0;
        foreach (var term in terms) {
            if (Match(term, title) is { } inTitle) {
                total += inTitle.Points;
                continue;
            }
            if (detail.Length > 0 && Match(term, detail) is { } inDetail) {
                total += Math.Max(0, inDetail.Points - DetailPenalty);
                continue;
            }
            return null;
        }
        return total / terms.Length;
    }

    /// Whether what was typed, as one text, starts `text`, ignoring case:
    /// "amazon" starts "amazon.de/" and "crest br" starts "Crest Browser".
    public bool Prefixes(string text) {
        ArgumentNullException.ThrowIfNull(text);
        if (IsEmpty) return false;
        var folded = new List<Rune>();
        foreach (var rune in text.EnumerateRunes()) folded.Add(IsWhitespace(rune) ? new Rune(' ') : Folded(rune));
        int position = 0;
        for (int index = 0; index < terms.Length; index++) {
            if (index > 0) {
                if (position >= folded.Count || folded[position] != new Rune(' ')) return false;
                while (position < folded.Count && folded[position] == new Rune(' ')) position++;
            }
            foreach (var rune in terms[index]) {
                if (position >= folded.Count || folded[position] != rune) return false;
                position++;
            }
        }
        return true;
    }

    /// How well one typed word abbreviates `title`: as the initials of its
    /// words ("tsv" for Toggle Split View), or as letters it holds in order;
    /// null for neither, or for more than one word or a single letter.
    public int? Abbreviates(string title) {
        ArgumentNullException.ThrowIfNull(title);
        if (terms.Length != 1 || terms[0].Length < 2) return null;
        var term = terms[0];
        List<Rune> initials = [];
        Rune? previous = null;
        foreach (var rune in title.EnumerateRunes()) {
            if (!IsBoundary(rune) && (previous is not { } before || IsBoundary(before))) initials.Add(Folded(rune));
            previous = rune;
        }
        if (initials.Count >= term.Length && term.Select((rune, index) => initials[index] == rune).All(matches => matches))
            return InitialsPoints;
        int found = 0;
        foreach (var rune in title.EnumerateRunes())
            if (found < term.Length && Folded(rune) == term[found]) found++;
        return found == term.Length ? SubsequencePoints : null;
    }

    /// The best place `term` appears in `text`: where it starts the text, where
    /// it starts a word, or anywhere else; null when it does not appear.
    private static TextMatch? Match(Rune[] term, string text) {
        TextMatch? best = null;
        Rune? previous = null;
        var runes = text.EnumerateRunes();
        int index = 0;
        foreach (var rune in runes) {
            if (Folded(rune) == term[0] && Matches(term, text, index)) {
                var match = previous is not { } before ? TextMatch.TextStart
                    : IsBoundary(before) ? TextMatch.WordStart : TextMatch.Inside;
                if (match == TextMatch.TextStart) return match;
                best = best?.Better(match) ?? match;
                if (best == TextMatch.WordStart) return best;
            }
            previous = rune;
            index += rune.Utf16SequenceLength;
        }
        return best;
    }

    /// Whether `term` appears in `text` from the UTF-16 offset `start`.
    private static bool Matches(Rune[] term, string text, int start) {
        int position = start;
        foreach (var expected in term) {
            if (position >= text.Length || Rune.DecodeFromUtf16(text.AsSpan(position), out var rune, out int length)
                != System.Buffers.OperationStatus.Done || Folded(rune) != expected) return false;
            position += length;
        }
        return true;
    }

    #endregion

    #region Actions - Folding

    private static Rune Folded(Rune rune) {
        if (rune.IsAscii) return rune.Value is >= 'A' and <= 'Z' ? new Rune(rune.Value + 32) : rune;
        if (rune == FinalSigma) return Sigma;
        return Rune.IsUpper(rune) ? Rune.ToLowerInvariant(rune) : rune;
    }

    private static bool IsWhitespace(Rune rune) => rune.IsAscii ? rune.Value is ' ' or '\t' : Rune.IsWhiteSpace(rune);

    /// A character that ends a word: anything but a letter or a number.
    private static bool IsBoundary(Rune rune) {
        if (rune.IsAscii) return !(rune.Value is >= '0' and <= '9' or >= 'A' and <= 'Z' or >= 'a' and <= 'z');
        return !(Rune.IsLetter(rune) || Rune.IsNumber(rune));
    }

    #endregion
}
