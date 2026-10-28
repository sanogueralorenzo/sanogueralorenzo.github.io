using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Spaces an import of `Profiles` from `Source` brings, read from the
/// files each profile names, without importing anything. A source that names
/// its own Spaces brings them as named there, those without tabs too; any
/// other brings one Space for each profile, holding its open tabs and as many
/// of its bookmarks, as saved tabs, as fit beside them, and named after it.
/// Chrome's and Arc's Spaces also offer the extensions their profile has
/// installed from the Chrome Web Store.
///
/// What fits is kept: the Spaces past the most a workspace holds, a Space
/// holding more than a Space keeps, a window that does not fit beside a
/// profile's others, bookmarks that do not fit, and a file that cannot be
/// read are each left out in `LeftOut`, named for their profile or Space, with
/// why, such as `SessionOverLimits`, `BookmarksOverLimits` or
/// `SessionUnrecognized`, while the rest come. When Chrome's latest session
/// cannot be read or holds no tab, the session before it is read instead.
///
/// The platform holds any access the files need while the core reads them,
/// and asks away from the main thread: the core answers without waiting for
/// any other work. Refused only when nothing could be brought: with the
/// reason the last profile or Space was left out, or `SessionHasNoTabs` when
/// no profile names a file.
public sealed record ReadImport(ImportSource Source, IReadOnlyList<ImportProfile> Profiles) : Query<ImportedSpaces> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override ImportedSpaces Answer(CrestApp app) {
        var portability = app.Portability;
        return InstalledBrowser.Of(Source).Read(Profiles, portability.Names(Source), portability.Ids, portability.Clock.Now);
    }

    #endregion
}
