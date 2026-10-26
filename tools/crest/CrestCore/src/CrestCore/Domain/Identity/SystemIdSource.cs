namespace CrestCore.Domain;

public sealed class SystemIdSource : IIdSource {
    #region Actions - Identity

    public Guid Next() => Guid.NewGuid();

    #endregion
}
