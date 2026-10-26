namespace CrestCore.Contracts;

#region Rejections

/// The Space has no usable custom search engine with this identity, or the
/// intent named no engine or two.
public sealed record UnknownSearchEngine(Guid? EngineId) : Rejection;

#endregion
