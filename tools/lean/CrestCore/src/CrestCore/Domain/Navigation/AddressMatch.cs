namespace CrestCore.Domain;

/// A known address that completes what was typed: the text completing it
/// leaves, the address that text opens, which keeps the `www.` and scheme the
/// text leaves out, and how closely it matches, from a host that merely
/// starts with what was typed to a typed path.
public sealed record AddressMatch(AddressCandidate Candidate, string Text, string Opens, int Quality) {
    #region Actions - Ranking

    /// Whether this completion ranks above `other`, with `use` reading how
    /// much a candidate was used: a closer match, then a better source, more
    /// use, a later date, and then the shorter, earlier text and address, so
    /// the order never depends on where a candidate was found.
    public bool Outranks(AddressMatch other, Func<AddressCandidate, double> use) {
        ArgumentNullException.ThrowIfNull(other);
        ArgumentNullException.ThrowIfNull(use);
        if (Quality != other.Quality) return Quality > other.Quality;
        if (Candidate.Source != other.Candidate.Source) return Candidate.Source > other.Candidate.Source;
        double own = use(Candidate), theirs = use(other.Candidate);
        if (Math.Abs(own - theirs) > 0.001) return own > theirs;
        if (Candidate.Date != other.Candidate.Date) return Candidate.Date > other.Candidate.Date;
        if (Text.Length != other.Text.Length) return Text.Length < other.Text.Length;
        int text = string.CompareOrdinal(Text, other.Text);
        if (text != 0) return text < 0;
        return string.CompareOrdinal(Candidate.Url, other.Candidate.Url) < 0;
    }

    #endregion
}
