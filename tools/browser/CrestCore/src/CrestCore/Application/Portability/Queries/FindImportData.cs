using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The profiles and password stores `Source` keeps in `Folder`, the folder
/// where the browser keeps its data. The platform holds any access the folder
/// needs while the core looks; a folder that is missing or unreadable holds
/// none.
public sealed record FindImportData(ImportSource Source, string Folder) : StandaloneQuery<ImportData> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override ImportData Answer(StandaloneContext context) => InstalledBrowser.Of(Source).Find(Folder);

    #endregion
}
