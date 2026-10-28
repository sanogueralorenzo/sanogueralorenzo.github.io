using CrestCore.Application;

namespace CrestCore.Contracts;

/// A live or blocked download failed, for `Reason` when it is known, with the
/// engine's or platform's own `Message` when it has one; one of the two is
/// given. A blocked automatic download fails when its retry can no longer be
/// replayed.
public sealed record FailDownload(Guid DownloadId, DownloadFailure? Reason, string? Message) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.Fail(DownloadId, Reason, Message), changes);

    #endregion
}
