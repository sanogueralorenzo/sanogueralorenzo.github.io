using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Arc's sidebar, `StorableSidebar.json`: containers of items, and Spaces
/// whose sections list the items they hold. Each Space brings its favorites
/// as pinned tabs, its pinned section as saved tabs in their folders, and its
/// unpinned section as open tabs, with its name, icon and colors, and each
/// split view as a split of its tabs. A Chromium session file Arc wrote is
/// read as one.
internal static class ArcSidebar {
    #region Static Variables

    /// The SF Symbol each of Arc's built-in Space icons stands for.
    private static readonly IReadOnlyDictionary<string, string> IconSymbols = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["planet"] = "globe.americas.fill",
        ["briefcase"] = "briefcase.fill",
        ["book"] = "book.fill",
        ["code"] = "chevron.left.forwardslash.chevron.right"
    };

    private const string DefaultSymbol = "sidebar.left";
    private const string UntitledFolder = "Untitled Folder";
    private const string UnpinnedSection = "unpinned";
    private const string PinnedSection = "pinned";

    #endregion

    #region Types

    private sealed record Item(string? Title, IReadOnlyList<string> Children, Content? Content);

    private sealed record Content(ArcTab? Tab, bool IsFolder, bool IsSplit);

    private sealed record ArcTab(string Title, string? Url, JsonElement? LastActive);

    private sealed record Space(string? Title, IReadOnlyList<string> Sections, string ProfileKey, string? ProfileFolder,
        JsonElement? CustomInfo);

    private sealed class Draft {
        public List<SessionFolder> Folders { get; } = [];
        public List<SessionTab> Tabs { get; } = [];
        public HashSet<string> Visited { get; } = new(StringComparer.Ordinal);
    }

    #endregion

    #region Actions - Reading

    /// The Spaces the sidebar holds, in order, however many: those past the
    /// most a workspace holds with their names alone, which an import leaves
    /// out. A Space holding more than a Space keeps holds one tab or folder
    /// past it, so an import leaves it out. Throws `Rejected` with
    /// `SessionUnrecognized` for a file that is not Arc's sidebar.
    public static IReadOnlyList<SessionDraft> Read(byte[] contents, DateTimeOffset importedAt) {
        if (ChromiumSession.Recognizes(contents)) return ChromiumSession.Read(contents, importedAt);
        using var document = ImportJson.Parse(contents) ?? throw new Rejected(new SessionUnrecognized());
        var sidebar = ImportJson.Object(ImportJson.Member(document.RootElement, "sidebar"));
        var containers = ImportJson.Array(ImportJson.Member(sidebar, "containers")) ?? throw new Rejected(new SessionUnrecognized());
        if (sidebar is null) throw new Rejected(new SessionUnrecognized());
        List<SessionDraft> drafts = [];
        foreach (var container in containers.Where(value => value.ValueKind == JsonValueKind.Object)) {
            // An identity Arc lists twice names its later record.
            Dictionary<string, Item> items = new(StringComparer.Ordinal);
            foreach (var (value, id) in Objects(ImportJson.Member(container, "items")))
                if (id is not null) items[id] = ReadItem(value);
            var favorites = Favorites(ImportJson.Member(container, "topAppsContainerIDs"));
            int spaceIndex = 0;
            foreach (var (value, _) in Objects(ImportJson.Member(container, "spaces"))) {
                var space = ReadSpace(value);
                spaceIndex++;
                string name = space.Title ?? $"Arc Space {spaceIndex}";
                if (drafts.Count >= BrowserDataFile.MaximumSpaces) {
                    drafts.Add(new SessionDraft(drafts.Count + 1, name, [], []));
                    continue;
                }
                var draft = new Draft();
                if (favorites.TryGetValue(space.ProfileKey, out var favoriteRoot))
                    Append(favoriteRoot, TabPlacement.Pinned, parent: null, depth: 0, items, draft, importedAt);
                var placement = TabPlacement.Current;
                foreach (var section in space.Sections) {
                    if (section == UnpinnedSection) placement = TabPlacement.Current;
                    else if (section == PinnedSection) placement = TabPlacement.Saved;
                    else Append(section, placement, parent: null, depth: 0, items, draft, importedAt);
                }
                string symbol = Symbol(space.CustomInfo);
                var colors = Colors(space.CustomInfo);
                drafts.Add(new SessionDraft(drafts.Count + 1, name, draft.Folders, draft.Tabs,
                    symbol, colors.Count == 0 ? null : SpaceAccent.Nearest(colors[0]), Look(colors), space.ProfileFolder));
            }
        }
        return drafts;
    }

    /// Arc lists records either as an array alternating identities and
    /// records, or as an object keyed by identity. Each record comes with its
    /// own identity, or the one listed for it.
    private static IEnumerable<(JsonElement Value, string? Id)> Objects(JsonElement? value) {
        if (ImportJson.Array(value) is { } array) {
            string? pending = null;
            foreach (var item in array) {
                if (item.ValueKind == JsonValueKind.String) {
                    pending = item.GetString();
                } else if (item.ValueKind == JsonValueKind.Object) {
                    yield return (item, item.TryGetProperty("id", out var own) ? ImportJson.Text(own) : pending);
                    pending = null;
                }
            }
            yield break;
        }
        foreach (var member in ImportJson.Members(value))
            if (member.Value.ValueKind == JsonValueKind.Object)
                yield return (member.Value, member.Value.TryGetProperty("id", out var own) ? ImportJson.Text(own) : member.Name);
    }

    private static Item ReadItem(JsonElement value) {
        var data = ImportJson.Object(ImportJson.Member(value, "data"));
        Content? content = null;
        if (data is not null) {
            var tab = ImportJson.Object(ImportJson.Member(data, "tab"));
            content = new(tab is null ? null : new ArcTab(
                ImportJson.Text(ImportJson.Member(tab, "savedTitle")) ?? ImportJson.Text(ImportJson.Member(value, "title")) ?? "",
                ImportJson.Text(ImportJson.Member(tab, "savedURL")),
                ImportJson.Member(tab, "timeLastActiveAt") ?? ImportJson.Member(value, "createdAt")),
                ImportJson.Object(ImportJson.Member(data, "list")) is not null,
                ImportJson.Object(ImportJson.Member(data, "splitView")) is not null);
        }
        return new(ImportJson.Text(ImportJson.Member(value, "title")), Strings(ImportJson.Member(value, "childrenIds")), content);
    }

    private static Space ReadSpace(JsonElement value) {
        var sections = Strings(ImportJson.Member(value, "containerIDs"));
        return new(ImportJson.Text(ImportJson.Member(value, "title")),
            sections.Count == 0 ? Strings(ImportJson.Member(value, "newContainerIDs")) : sections,
            ProfileKey(ImportJson.Member(value, "profile")), ProfileFolder(ImportJson.Member(value, "profile")),
            ImportJson.Object(ImportJson.Member(value, "customInfo")));
    }

    /// The favorites root of each profile, from pairs of a profile and its
    /// root's identity.
    private static Dictionary<string, string> Favorites(JsonElement? value) {
        Dictionary<string, string> favorites = new(StringComparer.Ordinal);
        var pairs = ImportJson.Array(value) ?? [];
        for (int index = 0; index + 1 < pairs.Count; index += 2)
            if (ImportJson.Text(pairs[index + 1]) is { } id) favorites[ProfileKey(pairs[index])] = id;
        return favorites;
    }

    /// Which of Arc's profiles a value names.
    private static string ProfileKey(JsonElement? value) {
        if (ImportJson.Object(value) is null) return "unknown";
        if (ImportJson.Flag(ImportJson.Member(value, "default")) == true) return "default";
        var details = ImportJson.Member(ImportJson.Member(value, "custom"), "_0");
        return $"custom:{ImportJson.Text(ImportJson.Member(details, "machineID")) ?? ""}:"
            + $"{ImportJson.Text(ImportJson.Member(details, "directoryBasename")) ?? ""}";
    }

    /// The folder in Arc's `User Data` of the profile a value names, other
    /// than the first, where its name is a plain folder name.
    private static string? ProfileFolder(JsonElement? value) {
        var details = ImportJson.Member(ImportJson.Member(value, "custom"), "_0");
        string? name = ImportJson.Text(ImportJson.Member(details, "directoryBasename"));
        return name is { Length: > 0 } && name != "." && name != ".." && name.IndexOfAny(['/', '\\']) < 0 ? name : null;
    }

    private static List<string> Strings(JsonElement? value) =>
        [.. (ImportJson.Array(value) ?? []).Select(item => ImportJson.Text(item)).OfType<string>()];

    #endregion

    #region Actions - Tabs

    /// Adds the item `id` names: a tab where it is one, a folder holding its
    /// children where it is a folder in the pinned section, the tabs of a
    /// split view in that split, and otherwise its children in its place.
    private static void Append(string id, TabPlacement placement, string? parent, int depth, IReadOnlyDictionary<string, Item> items,
        Draft draft, DateTimeOffset importedAt, string? split = null) {
        if (depth >= FolderTree.MaximumDepth || !draft.Visited.Add(id) || !items.TryGetValue(id, out var item)
            || item.Content is not { } content) return;
        if (content.Tab is { Url: { } url } tab && ImportAddress.Read(url) is { } address) {
            if (draft.Tabs.Count > SessionDraft.MaximumTabs) return;
            var time = ImportJson.Number(tab.LastActive) is { } raw && double.IsFinite(raw) ? ImportDate.FromUnixOrReferenceSeconds(raw)
                : null;
            draft.Tabs.Add(new SessionTab(tab.Title, address, placement, placement == TabPlacement.Saved ? parent : null,
                time ?? importedAt, split));
            return;
        }
        if (content.IsSplit) {
            foreach (var child in item.Children) Append(child, placement, parent, depth, items, draft, importedAt, id);
            return;
        }
        if (content.IsFolder && placement == TabPlacement.Saved) {
            if (draft.Folders.Count > FolderTree.MaximumCount) return;
            draft.Folders.Add(new SessionFolder(id, item.Title ?? UntitledFolder, parent));
            foreach (var child in item.Children) Append(child, placement, id, depth + 1, items, draft, importedAt);
            return;
        }
        foreach (var child in item.Children) Append(child, placement, parent, depth, items, draft, importedAt);
    }

    #endregion

    #region Actions - Looks

    private static string Symbol(JsonElement? customInfo) {
        var icon = ImportJson.Member(customInfo, "iconType");
        if (ImportJson.Text(ImportJson.Member(icon, "emoji_v2")) is { Length: > 0 } emoji) return EmojiIcon.Chosen(emoji)?.Symbol ?? emoji;
        return ImportJson.Text(ImportJson.Member(icon, "icon")) is { } name && IconSymbols.TryGetValue(name, out var symbol)
            ? symbol : DefaultSymbol;
    }

    /// The Space's colors: its gradient's base colors, else its single color,
    /// else its palette's mid tone, at most as many as a look keeps.
    private static List<BrandColor> Colors(JsonElement? customInfo) {
        var theme = ImportJson.Member(customInfo, "windowTheme");
        var color = Path(theme, "background", "single", "_0", "style", "color", "_0");
        List<BrandColor> colors = [];
        if (ImportJson.Array(Path(color, "blendedGradient", "_0", "baseColors")) is { } gradient) {
            colors.AddRange(gradient.Select(item => Color(item)).OfType<BrandColor>());
        } else if (ImportJson.Object(ImportJson.Member(color, "blendedSingleColor")) is not null
            && ImportJson.Member(ImportJson.Member(ImportJson.Member(color, "blendedSingleColor"), "_0"), "color") is { } single) {
            if (Color(single) is { } parsed) colors.Add(parsed);
        }
        if (colors.Count == 0 && Color(ImportJson.Member(ImportJson.Member(theme, "primaryColorPalette"), "midTone")) is { } midTone)
            colors.Add(midTone);
        return [.. colors.Take(SpaceBranding.MaximumColorCount)];
    }

    private static JsonElement? Path(JsonElement? value, params string[] keys) {
        foreach (string key in keys) value = ImportJson.Member(value, key);
        return value;
    }

    private static BrandColor? Color(JsonElement? value) =>
        ImportJson.Object(value) is not null && ImportJson.Number(ImportJson.Member(value, "red")) is { } red
            && ImportJson.Number(ImportJson.Member(value, "green")) is { } green
            && ImportJson.Number(ImportJson.Member(value, "blue")) is { } blue
            ? new(Unit(red), Unit(green), Unit(blue), Unit(ImportJson.Number(ImportJson.Member(value, "alpha")) ?? 1)) : null;

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    /// A diagonal gradient banner of several colors, or a solid banner of one.
    private static SpaceBranding? Look(IReadOnlyList<BrandColor> colors) => colors.Count == 0 ? null : SpaceBranding.Painted(colors,
        colors.Count > 1 ? SpaceBannerPattern.Diagonal : SpaceBannerPattern.Solid, strength: 1, SpaceBranding.LegacyReadabilityFade,
        colors.Count > 1 ? SpaceThemeMode.Gradient : SpaceThemeMode.Banner, gradientAngle: 45, showsTexture: false);

    #endregion
}
