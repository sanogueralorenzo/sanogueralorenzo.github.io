namespace CrestCore.Domain;

public interface IClock {
    #region Variables

    DateTimeOffset Now { get; }

    #endregion
}
