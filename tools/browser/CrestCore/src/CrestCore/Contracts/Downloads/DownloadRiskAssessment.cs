namespace CrestCore.Contracts;

/// The filename a download is saved under and every reason it looks dangerous,
/// in `DownloadRiskReason.All` order. No reasons means the file is ordinary.
public sealed record DownloadRiskAssessment(string SanitizedFilename, IReadOnlyList<DownloadRiskReason> Reasons) {
    #region Actions - Assessment

    /// Every reason that applies to the platform's facts. Refuses facts the
    /// ledger could not record.
    public static DownloadRiskAssessment Of(DownloadRiskFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        facts.Validate();
        return new(facts.SanitizedFilename, [.. DownloadRiskReason.All.Where(reason => reason.Applies(facts))]);
    }

    /// Whether the person must confirm the download before it continues.
    public bool RequiresConfirmation(bool isUserInitiated) => Reasons.Any(reason => reason.RequiresConfirmation(isUserInitiated));

    #endregion
}
