namespace CrestCore.Contracts;

/// What the platform's URL parser reports about a candidate local document:
/// whether it is a `file:` URL, whether it names a user, whether its path is
/// non-empty, and its host (null or empty when it has none).
public sealed record LocalDocumentFacts(bool IsFile, bool HasUser, bool HasPath, string? Host) {
    #region Variables

    /// Whether Crest opens the address as a document (Finder, Open With, the
    /// Open panel), never as a web link. Remote authorities are refused;
    /// `file://localhost/…` is this device spelled the long way round.
    internal bool IsAcceptedDocument {
        get {
            if (!IsFile || HasUser || !HasPath || Host is { Length: > ExternalWebLink.MaximumHostLength }) return false;
            return string.IsNullOrEmpty(Host) || string.Equals(Host, "localhost", StringComparison.OrdinalIgnoreCase);
        }
    }

    #endregion
}
