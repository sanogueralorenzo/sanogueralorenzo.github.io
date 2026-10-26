using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Reading other browsers' data and Crest's own browser-data files, and
/// writing exports. Reading changes nothing and holds no lock, so the
/// platform asks away from the main thread while the core goes on; the Spaces
/// it reads reach a workspace only through `ImportSpaces` and the other
/// imports, which check them again.
internal sealed class Portability(IReadOnlyList<ImportSpaceNames>? names, IClock clock, IIdSource ids) {
    #region Variables

    /// The time an import stamps what it reads with.
    internal IClock Clock => clock;

    /// Where the identities an import gives what it reads come from.
    internal IIdSource Ids => ids;

    #endregion

    #region Actions - Queries

    /// The file `format` writes of `session`, exported now.
    public ExportedDocument Export(SessionState session, ExportFormat format) => ExportWriter.Of(format).Write(session, clock.Now);

    /// The names `source`'s Spaces take in the person's language, or its
    /// English names when the platform gave none.
    internal ImportSpaceNames Names(ImportSource source) =>
        names?.FirstOrDefault(entry => entry.Source == source)
        ?? new(source, source.SpaceName ?? source.Title, source.NumberedSpaceName ?? source.Title);

    #endregion
}
