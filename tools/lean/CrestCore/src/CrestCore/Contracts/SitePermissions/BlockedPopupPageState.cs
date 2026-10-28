namespace CrestCore.Contracts;

/// Document-scoped blocked-popup state for one page. `Status` and `Origin`
/// are both null when no indication is shown. `IndicationRevision` advances
/// once per new indication so the page announces it once.
public sealed record BlockedPopupPageState(BlockedPopupStatus? Status, SiteOrigin? Origin, string? DocumentIdentifier,
    int IndicationRevision) {
    #region Static Variables

    public const int MaximumDocumentIdentifierLength = 128;

    public static readonly BlockedPopupPageState Empty = new(null, null, null, 0);

    #endregion

    #region Actions - Popups

    /// The state after `popupEvent`, as a page's blocked-popup notice moves
    /// with each popup event, or null when it changes nothing. An event that
    /// starts an indication needs the document identifier and the blocked
    /// site's origin, a state names a status and an origin together or
    /// neither, and every origin must be one the rules can read; otherwise
    /// `InvalidBlockedPopup`.
    internal BlockedPopupPageState? Applying(BlockedPopupEvent popupEvent, string? documentIdentifier, SiteOrigin? origin) {
        ArgumentNullException.ThrowIfNull(popupEvent);
        if ((Status is null) != (Origin is null) || Origin is { IsValid: false } || origin is { IsValid: false }
            || DocumentIdentifier is { Length: > MaximumDocumentIdentifierLength }
            || popupEvent.StartsIndication && (string.IsNullOrEmpty(documentIdentifier)
                || documentIdentifier.Length > MaximumDocumentIdentifierLength || origin is null))
            throw new Rejected(new InvalidBlockedPopup());
        bool applies = popupEvent.FromAnything ? Status is not null || DocumentIdentifier is not null : Status == popupEvent.From;
        if (!applies) return null;
        if (popupEvent.StartsIndication) return new(popupEvent.To, origin, documentIdentifier, unchecked(IndicationRevision + 1));
        return popupEvent.To is { } status
            ? this with { Status = status }
            : this with { Status = null, Origin = null, DocumentIdentifier = null };
    }

    #endregion
}
