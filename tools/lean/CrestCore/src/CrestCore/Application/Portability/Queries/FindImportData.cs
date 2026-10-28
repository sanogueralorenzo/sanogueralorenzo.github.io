using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record FindImportData(ImportSource Source, string Folder) : StandaloneQuery<ImportData> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override ImportData Answer(StandaloneContext context) => InstalledBrowser.Of(Source).Find(Folder);

    #endregion
}
