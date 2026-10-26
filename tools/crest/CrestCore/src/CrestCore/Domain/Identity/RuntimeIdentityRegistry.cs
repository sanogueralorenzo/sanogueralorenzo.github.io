namespace CrestCore.Domain;

/// First occurrences retain identity. A collision receives a fresh identity
/// without inheriting another page's or profile's runtime resources.
public sealed class RuntimeIdentityRegistry(IIdSource ids) {
    #region Variables

    private readonly HashSet<Guid> seen = [];

    #endregion

    #region Actions - Identity

    public Guid Claim(Guid preferred) {
        if (preferred != Guid.Empty && seen.Add(preferred)) return preferred;
        Guid replacement;
        do { replacement = ids.Next(); } while (replacement == Guid.Empty || !seen.Add(replacement));
        return replacement;
    }

    #endregion
}
