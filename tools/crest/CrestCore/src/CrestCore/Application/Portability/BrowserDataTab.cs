using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A tab as a Crest browser-data file keeps it: identities as the file spells
/// them, which an import replaces, and addresses spelled as an import keeps
/// them.
internal sealed record BrowserDataTab(Guid Id, string Title, NativeTabContent? NativeContent, string? Url, string? SavedUrl,
    string Symbol, TabPlacement Placement, Guid? FolderId, Guid? SplitGroupId, DateTimeOffset LastActivatedAt) {
    #region Static Variables

    /// What a tab showing neither a page nor a native view is called and shows.
    private const string StartPageTitle = "Start Page";
    private const string StartPageSymbol = "flag.fill";

    /// The longest kind of native view a file names.
    private const int MaximumNativeKind = 128;

    #endregion

    #region Actions - Reading

    public static BrowserDataTab Read(BrowserDataValue value) {
        var native = value.OptionalNested("nativeContent") is { } content
            ? new NativeTabContent(content.Text("kind"), content.OptionalIdentity("resourceID")) : null;
        var placement = TabPlacement.Named(value.Text("placement")) ?? throw BrowserDataValue.Invalid();
        return new(value.Identity("id"), value.Text("title"), native, value.OptionalText("url"), value.OptionalText("savedURL"),
            value.Text("symbol"), placement, value.OptionalIdentity("folderID"), value.OptionalIdentity("splitGroupID"),
            value.Date("lastActivatedAt"));
    }

    /// The tab a Space keeps, with its new identity and the folder and split
    /// it joins, which `folders` and `splits` map from the file's. Throws
    /// `ArchiveInvalid` for anything a Space would not keep.
    public TabState Materialize(Guid id, IReadOnlyDictionary<Guid, Guid> folders, IReadOnlyDictionary<Guid, Guid> splits) {
        Require(ImportText.IsKept(Title, ImportText.MaximumTitle) && ImportText.IsKept(Symbol, ImportText.MaximumSymbol));
        if (NativeContent is { } native)
            Require(ImportText.IsKept(native.Kind, MaximumNativeKind) && Url is null && SavedUrl is null);
        Require(ImportAddress.TryReadStored(Url, removesFragment: false, out var url));
        Require(ImportAddress.TryReadStored(SavedUrl, removesFragment: false, out var saved));
        Guid? folder = null;
        if (Placement.HoldsFolders && FolderId is { } source) folder = folders.TryGetValue(source, out var mapped) ? mapped
            : throw BrowserDataValue.Invalid();
        else Require(FolderId is null);
        bool isStartPage = NativeContent is null && url is null;
        string? address = url?.Spelling;
        return new(id, isStartPage ? StartPageTitle : Title, address, NativeContent,
            NativeContent is null && Placement.IsDurable ? saved?.Spelling ?? address : null,
            isStartPage ? StartPageSymbol : Symbol, FaviconUrl: null, IconAccent: null, StoredIconMode: null, Placement, folder,
            SplitGroupId is { } split && splits.TryGetValue(split, out var group) ? group : null, LastActivatedAt,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false);
    }

    /// A Start Page, which a Space that brings no tab shows.
    public static TabState StartPage(Guid id, DateTimeOffset now) => new(id, StartPageTitle, Url: null, NativeContent: null,
        SavedUrl: null, StartPageSymbol, FaviconUrl: null, IconAccent: null, StoredIconMode: null, TabPlacement.Current,
        FolderId: null, SplitGroupId: null, now, PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null,
        KeepsPageLoaded: false);

    private static void Require(bool condition) {
        if (!condition) throw BrowserDataValue.Invalid();
    }

    #endregion

    #region Actions - Writing

    /// The tab as a file keeps it: its page's title, and its addresses without
    /// credentials. A saved or pinned tab keeps the address it was saved at.
    public static BrowserDataTab From(TabState tab) {
        ArgumentNullException.ThrowIfNull(tab);
        string? saved = tab.SavedUrl ?? (tab.Placement.IsDurable ? tab.Url : null);
        return new(tab.Id, tab.Title, tab.NativeContent, ImportAddress.Written(tab.Url, removesFragment: false),
            ImportAddress.Written(saved, removesFragment: false), tab.Symbol, tab.Placement, tab.FolderId, tab.SplitGroupId,
            tab.LastActivatedAt);
    }

    public JsonObject Write() {
        var value = new JsonObject { ["id"] = BrowserDataFile.Identity(Id), ["title"] = Title };
        if (NativeContent is { } native) {
            var content = new JsonObject { ["kind"] = native.Kind };
            if (native.ResourceId is { } resource) content["resourceID"] = BrowserDataFile.Identity(resource);
            value["nativeContent"] = content;
        }
        if (Url is not null) value["url"] = Url;
        if (SavedUrl is not null) value["savedURL"] = SavedUrl;
        value["symbol"] = Symbol;
        value["placement"] = Placement.Name;
        if (FolderId is { } folder) value["folderID"] = BrowserDataFile.Identity(folder);
        if (SplitGroupId is { } split) value["splitGroupID"] = BrowserDataFile.Identity(split);
        value["lastActivatedAt"] = ImportDate.UnixMilliseconds(LastActivatedAt);
        return value;
    }

    #endregion
}
