using CrestCore.Contracts;

namespace CrestCore.Application;

/// One site's engine choice. A choice the device store keeps names no Space
/// and holds for every Space; one a memory-only Space made names that Space.
internal sealed record SiteEngineChoice(Guid? SpaceId, SiteOrigin Origin, EngineKind Engine);

/// Engine choices in the order they were made, least recent first. Past
/// `Maximum`, the least recently chosen goes. Not thread-safe: the device
/// lock guards it.
internal sealed class SiteEngineLedger {
    #region Static Variables

    /// The most choices a ledger holds.
    public const int Maximum = 512;

    #endregion

    #region Variables

    private readonly List<SiteEngineChoice> choices = [];

    /// Every choice, least recent first.
    public IReadOnlyList<SiteEngineChoice> Choices => choices;

    #endregion

    #region Actions - Choices

    /// Replaces whatever the ledger held with `kept`.
    public void Restore(IEnumerable<SiteEngineChoice> kept) {
        choices.Clear();
        foreach (var choice in kept) Choose(choice);
    }

    /// Records `choice` as the most recent for its Space and origin, and says
    /// whether the ledger changed.
    public bool Choose(SiteEngineChoice choice) {
        if (choices.Count > 0 && choices[^1] == choice) return false;
        choices.RemoveAll(held => held.SpaceId == choice.SpaceId && held.Origin == choice.Origin);
        choices.Add(choice);
        if (choices.Count > Maximum) choices.RemoveRange(0, choices.Count - Maximum);
        return true;
    }

    /// The engine chosen for `origin` in `spaceId`, or null when none is.
    public EngineKind? Chosen(Guid? spaceId, SiteOrigin origin) =>
        choices.LastOrDefault(choice => choice.SpaceId == spaceId && choice.Origin == origin)?.Engine;

    /// Forgets an explicit choice, so the site follows the default again.
    public bool Forget(Guid? spaceId, SiteOrigin origin) =>
        choices.RemoveAll(choice => choice.SpaceId == spaceId && choice.Origin == origin) > 0;

    #endregion
}
