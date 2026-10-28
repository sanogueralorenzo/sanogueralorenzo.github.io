using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The browsers among `Apps` that keep a Chromium browser's data below the
/// Application Support folder of `Home`, other than the browsers setup lists,
/// each with the profiles it keeps there, by name. An app keeping none is left
/// out.
public sealed record FindChromiumBrowsers(string Home, IReadOnlyList<ImportBrowserApp> Apps)
    : StandaloneQuery<IReadOnlyList<ImportFoundBrowser>> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override IReadOnlyList<ImportFoundBrowser> Answer(StandaloneContext context) => InstalledBrowser.FindUnlisted(Home, Apps);

    #endregion
}
