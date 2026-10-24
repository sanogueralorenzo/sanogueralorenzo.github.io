namespace CrestCore.Contracts;

/// The most bytes one encoded intent or query of the marked type may take.
/// Messages are small, so a type without the attribute takes at most
/// `DefaultBytes`; anything larger is a caller bug the core refuses before
/// reading it. The generator writes each limit into the codec the dispatcher
/// reads, and into the schema fingerprint.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class MessageLimitAttribute(int bytes) : Attribute {
    #region Variables

    /// The limit of every intent and query that names none.
    public const int DefaultBytes = 16 * 1024 * 1024;

    public int Bytes { get; } = bytes;

    #endregion
}
