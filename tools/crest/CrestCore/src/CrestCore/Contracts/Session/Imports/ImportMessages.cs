namespace CrestCore.Contracts;

#region Queries

/// The session an import would leave: `Session`, the tabs it would place from
/// its Spaces, and the workspace's own tabs that would take a new identity.
public sealed record ImportedWorkspace(SessionState Session, IReadOnlyList<ImportedTab> Imported, IReadOnlyList<TabCopied> Copied);

#endregion

#region Rejections

/// The import's Spaces or choices cannot be read, for the reason `Flaw` names.
public sealed record InvalidImport(ImportFlaw Flaw) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t read the Spaces to import.";

    #endregion
}

/// Why the core cannot read an import.
public enum ImportFlaw {
    /// Its Spaces are not Spaces in the stored format.
    Unreadable,
    /// A Space holds a split whose tabs are not one run of open tabs, which
    /// repair would rewrite.
    MalformedSplit,
    /// A choice names a Space the import does not bring, a Space it brings has
    /// no choice, or two of its Spaces share an identity, so a choice cannot
    /// tell them apart.
    UnpairedChoices
}

/// A reviewed import includes none of its Spaces.
public sealed record NoIncludedSpaces : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Choose at least one Space to import.";

    #endregion
}

/// Another Space already uses the profile `ProfileId`, and a profile belongs
/// to one Space.
public sealed record ProfileInUse(Guid ProfileId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Another Space already uses this Space’s browsing data.";

    #endregion
}

#endregion

#region Models

/// A tab an import placed, `TabId`, and the tab it came from: `SourceTabId`,
/// open or archived, of the import's Space at position `Source` among its
/// Spaces.
public sealed record ImportedTab(Guid TabId, int Source, Guid SourceTabId);

/// A reviewed tab that moves to `Placement`.
public sealed record TabPlacementChoice(Guid TabId, TabPlacement Placement);

#endregion
