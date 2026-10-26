namespace CrestCore.Contracts;

/// A file's contents, to save as `Format` names.
public sealed record ExportedDocument(byte[] Contents, ExportFormat Format);

/// What a browser keeps in its data folder: each profile with the files an
/// import reads, and each store of saved passwords, in the order a person
/// meets them there.
public sealed record ImportData(IReadOnlyList<ImportProfile> Profiles, IReadOnlyList<ImportPasswordStore> PasswordStores);

/// A profile's store of saved passwords: `Id`, the name the browser keeps the
/// profile under, the `ProfileName` the person gave it, and the store's path.
public sealed record ImportPasswordStore(string Id, string ProfileName, string Path);

/// One profile of a browser: `Id`, the name the browser keeps it under, the
/// `Name` the person gave it, and the paths of its bookmarks and of its latest
/// session, where it keeps either. A profile keeps at least one. A browser
/// built on Chromium also names the profile's own folder, `ProfilePath`,
/// where its installed extensions are kept.
public sealed record ImportProfile(string Id, string Name, string? BookmarksPath, string? SessionPath, string? ProfilePath = null);

/// An app on the Mac that opens web pages, which setup may find keeping a
/// Chromium browser's data: its `BundleIdentifier` and the `Name` it shows.
public sealed record ImportBrowserApp(string BundleIdentifier, string Name);

/// A browser setup does not list that keeps Chromium's data in `DataFolder`:
/// the app, by `BundleIdentifier` and `Name`, and the profiles found there.
public sealed record ImportFoundBrowser(string BundleIdentifier, string Name, string DataFolder, ImportData Data);

/// The Spaces an import would bring, in order, each with new identities, the
/// way `ImportSpaces` takes them, the extensions each of those Spaces offers,
/// for those that offer any, and what the read left out, in the order it met
/// it.
public sealed record ImportedSpaces(IReadOnlyList<SpaceState> Spaces, IReadOnlyList<ImportSpaceExtensions> Extensions,
    IReadOnlyList<ImportLeftOut> LeftOut);

/// A profile or Space an import could not bring, or brought only in part, by
/// the `Name` the person knows it by, and the `Reason` it was left out, such
/// as `SessionOverLimits` for one past what a workspace or a Space keeps or
/// `BookmarksOverLimits` for bookmarks that did not all fit.
public sealed record ImportLeftOut(string Name, Rejection Reason);

/// The extensions another browser had installed where the Space `SpaceId`
/// comes from, in the order the browser lists them by name.
public sealed record ImportSpaceExtensions(Guid SpaceId, IReadOnlyList<ImportExtension> Extensions);

/// An extension from the Chrome Web Store: its `ExtensionId`, which is all
/// that is needed to install it again, the `Name` it shows, or its
/// identifier when it names none, and the path of the icon the other browser
/// keeps for it, `IconPath`, when it keeps one.
public sealed record ImportExtension(string ExtensionId, string Name, string? IconPath = null);

#region Models

/// How a review heads each Space an import brings: with the Space's own name
/// and look, or with a plain section label, for a browser whose Spaces are
/// sections of one sidebar.
public enum ImportSpaceHeaderStyle {
    Identity,
    SectionLabel
}

/// `Source`'s `SpaceName` and `NumberedSpaceName` in the person's language, as
/// the platform resolved them, so a Space an import names is stored as the
/// person reads it. `NumberedSpaceName` keeps its `%lld`.
public sealed record ImportSpaceNames(ImportSource Source, string SpaceName, string NumberedSpaceName);

#endregion
