using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A folder as a Crest browser-data file keeps it. A file from before
/// folders had a place, a color or a collapsed state reads as a saved,
/// expanded folder in the default color.
internal sealed record BrowserDataFolder(Guid Id, TabPlacement Location, string Title, string Symbol, BrandColor Color,
    Guid? ParentId, bool IsCollapsed, Guid? OrderAnchorTabId) {
    #region Actions - Reading

    public static BrowserDataFolder Read(BrowserDataValue value) {
        var location = value.OptionalText("location") is { } spelling
            ? TabPlacement.Named(spelling) is { HoldsFolders: true } holder ? holder : throw BrowserDataValue.Invalid()
            : TabPlacement.Saved;
        return new(value.Identity("id"), location, value.Text("title"), value.Text("symbol"),
            value.OptionalColor("color") ?? FolderState.DefaultColor, value.OptionalIdentity("parentID"),
            value.OptionalFlag("isCollapsed") ?? false, value.OptionalIdentity("orderAnchorTabID"));
    }

    /// The folder a Space keeps, with its new identity and parent. Throws
    /// `ArchiveInvalid` for a title or symbol a Space would not keep.
    public FolderState Materialize(Guid id, Guid? parentId) {
        if (!ImportText.IsKept(Title, ImportText.MaximumFolderTitle) || !ImportText.IsKept(Symbol, ImportText.MaximumSymbol))
            throw BrowserDataValue.Invalid();
        return new(id, Location, Title, Symbol, Color, parentId, IsCollapsed, CollapseModifiedAt: null, OrderAnchorTabId);
    }

    #endregion

    #region Actions - Writing

    public static BrowserDataFolder From(FolderState folder) {
        ArgumentNullException.ThrowIfNull(folder);
        return new(folder.Id, folder.Location, folder.Title, folder.DisplaySymbol, folder.DisplayColor, folder.ParentId,
            folder.IsCollapsed, folder.OrderAnchorTabId);
    }

    public JsonObject Write() {
        var value = new JsonObject {
            ["id"] = BrowserDataFile.Identity(Id),
            ["location"] = Location.Name,
            ["title"] = Title,
            ["symbol"] = Symbol,
            ["color"] = BrowserDataFile.Color(Color)
        };
        if (ParentId is { } parent) value["parentID"] = BrowserDataFile.Identity(parent);
        value["isCollapsed"] = IsCollapsed;
        if (OrderAnchorTabId is { } anchor) value["orderAnchorTabID"] = BrowserDataFile.Identity(anchor);
        return value;
    }

    #endregion
}
