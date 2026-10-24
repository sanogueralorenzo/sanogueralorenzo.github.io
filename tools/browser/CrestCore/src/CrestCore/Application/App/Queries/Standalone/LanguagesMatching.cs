using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether each of `Candidates` names the same translation language as
/// `Language`. It reads no state, so a host may ask it without an app.
public sealed record LanguagesMatching(string Language, IReadOnlyList<string> Candidates) : StandaloneQuery<LanguageMatches> {
    #region Actions - Answering

    internal override LanguageMatches Answer(StandaloneContext context) =>
        new([.. Candidates.Select(candidate => LanguageTag.Matches(Language, candidate))]);

    #endregion
}
