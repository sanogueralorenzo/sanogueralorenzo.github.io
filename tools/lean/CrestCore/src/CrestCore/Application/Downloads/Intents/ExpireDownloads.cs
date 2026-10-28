using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes finished, canceled, failed and blocked records whose age strictly
/// exceeds their profile's retention. When several Spaces share a profile the
/// shortest retention wins; a profile with no limit keeps its records.
public sealed record ExpireDownloads(DateTimeOffset Now, IReadOnlyList<DownloadRetention> Retentions)
    : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        Downloads.Removed(downloads.Ledger.RemoveExpired(Retentions, Now), changes);

    #endregion
}
