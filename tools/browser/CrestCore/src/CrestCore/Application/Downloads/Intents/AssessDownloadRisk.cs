using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records a live download's risk. Any reason makes it wait for approval under
/// its sanitized name.
public sealed record AssessDownloadRisk(Guid DownloadId, DownloadRiskAssessment Assessment) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.AssessRisk(DownloadId, Assessment), changes);

    #endregion
}
