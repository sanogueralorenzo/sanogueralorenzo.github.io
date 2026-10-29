namespace CrestCore.Contracts;

/// A native page's current appearance, captured by the issuing window for
/// copy/split edits. The session owns no renderer or duplicate live-page cache.
public sealed record TabPageAppearance(Guid TabId, string? Address, string Title);
