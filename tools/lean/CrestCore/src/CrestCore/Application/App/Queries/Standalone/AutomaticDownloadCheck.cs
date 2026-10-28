using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a download a page starts goes ahead, is refused or asks first:
/// whether a person's gesture started it or approved a retry, the site's saved
/// decision, and whether the page has already had its one automatic download
/// while that decision is Ask. This is Chrome-style automatic-download
/// throttling for one page and origin: while the site's saved decision is
/// still Ask, the first file it sends without a user gesture is allowed and any
/// further file must ask first. `HasAllowedAutomaticDownload` is the throttle
/// state the caller keeps per page, origin and Space. Callers without such a
/// scope pass false and discard the returned state.
public sealed record AutomaticDownloadCheck(bool UserInitiated, bool UserApprovedRetry, SitePermissionDecision SavedDecision,
    bool HasAllowedAutomaticDownload) : StandaloneQuery<AutomaticDownloadVerdict> {
    #region Variables

    internal AutomaticDownloadVerdict Verdict {
        get {
            // A fresh user action starts a fresh one-download allowance.
            bool allowance = !UserInitiated && HasAllowedAutomaticDownload;
            var action = Action(UserInitiated || UserApprovedRetry, allowance);
            if (!UserInitiated && !UserApprovedRetry && SavedDecision.Asks
                && action == AutomaticDownloadAction.Allow) allowance = true;
            return new(action, allowance);
        }
    }

    #endregion

    #region Actions - Answering

    internal override AutomaticDownloadVerdict Answer(StandaloneContext context) => Verdict;

    /// An approved download goes ahead, and so does one the saved decision
    /// grants. A saved block refuses it. Without an answer, the first automatic
    /// download goes ahead and any further one asks.
    private AutomaticDownloadAction Action(bool isUserApproved, bool hasAllowedAutomaticDownload) {
        if (isUserApproved || SavedDecision.Grants) return AutomaticDownloadAction.Allow;
        if (SavedDecision.Denies) return AutomaticDownloadAction.Deny;
        return hasAllowedAutomaticDownload ? AutomaticDownloadAction.RequestPermission : AutomaticDownloadAction.Allow;
    }

    #endregion
}
