namespace CrestCore.Domain;

public sealed class SystemClock : IClock {
    #region Variables

    public DateTimeOffset Now => DateTimeOffset.UtcNow;

    #endregion
}
