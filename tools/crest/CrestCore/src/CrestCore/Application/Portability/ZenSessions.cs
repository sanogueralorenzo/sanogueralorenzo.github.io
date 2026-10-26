using System.Globalization;
using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Zen's `zen-sessions.jsonlz4`: its Spaces, folders and tabs. Each Space
/// brings the Essentials as pinned tabs, its pinned tabs as saved tabs in
/// their folders, and its other tabs as open tabs, with its name and theme.
/// Zen keeps a split view as a group of its own, which is no folder: a pinned
/// tab in one is saved in the folder holding the split, or outside any folder
/// for a split among the Space's pinned tabs, and the split comes along as a
/// split of its tabs. A Space's icon is one of Zen's own, read as the SF
/// Symbol that draws the same thing, or an emoji.
internal static class ZenSessions {
    #region Static Variables

    private const string Symbol = "circle.hexagongrid.fill";
    /// Where Zen keeps the icons a Space may wear, each named as its file.
    private const string IconFolder = "zen-icons/selectable/";
    private const double ComponentScale = 255;

    /// The SF Symbol that draws each of Zen's Space icons.
    private static readonly IReadOnlyDictionary<string, string> IconSymbols = new Dictionary<string, string>(StringComparer.Ordinal) {
        ["airplane"] = "airplane",
        ["american-football"] = "football.fill",
        ["baseball"] = "baseball.fill",
        ["basket"] = "basket.fill",
        ["bed"] = "bed.double.fill",
        ["bell"] = "bell.fill",
        ["book"] = "book.fill",
        ["bookmark"] = "bookmark.fill",
        ["briefcase"] = "briefcase.fill",
        ["brush"] = "paintbrush.fill",
        ["bug"] = "ladybug.fill",
        ["build"] = "hammer.fill",
        ["cafe"] = "cup.and.saucer.fill",
        ["call"] = "phone.fill",
        ["card"] = "creditcard.fill",
        ["chat"] = "bubble.left.fill",
        ["checkbox"] = "checkmark.square.fill",
        ["circle"] = "circle.fill",
        ["cloud"] = "cloud.fill",
        ["code"] = "chevron.left.forwardslash.chevron.right",
        ["coins"] = "dollarsign.circle.fill",
        ["construct"] = "wrench.and.screwdriver.fill",
        ["cutlery"] = "fork.knife",
        ["egg"] = "frying.pan.fill",
        ["extension-puzzle"] = "puzzlepiece.extension.fill",
        ["eye"] = "eye.fill",
        ["fast-food"] = "takeoutbag.and.cup.and.straw.fill",
        ["fish"] = "fish.fill",
        ["flag"] = "flag.fill",
        ["flame"] = "flame.fill",
        ["flask"] = "flask.fill",
        ["folder"] = "folder.fill",
        ["game-controller"] = "gamecontroller.fill",
        ["globe"] = "globe",
        ["globe-1"] = "globe.americas.fill",
        ["grid-2x2"] = "square.grid.2x2.fill",
        ["grid-3x3"] = "square.grid.3x3.fill",
        ["heart"] = "heart.fill",
        ["ice-cream"] = "birthday.cake.fill",
        ["image"] = "photo.fill",
        ["inbox"] = "tray.fill",
        ["key"] = "key.fill",
        ["layers"] = "square.stack.3d.up.fill",
        ["leaf"] = "leaf.fill",
        ["lightning"] = "bolt.fill",
        ["location"] = "location.fill",
        ["lock-closed"] = "lock.fill",
        ["logo-github"] = "chevron.left.forwardslash.chevron.right",
        ["logo-rss"] = "dot.radiowaves.up.forward",
        ["logo-usd"] = "dollarsign",
        ["mail"] = "envelope.fill",
        ["map"] = "map.fill",
        ["megaphone"] = "megaphone.fill",
        ["moon"] = "moon.fill",
        ["music"] = "music.note",
        ["navigate"] = "location.north.fill",
        ["nuclear"] = "atom",
        ["page"] = "doc.fill",
        ["palette"] = "paintpalette.fill",
        ["paw"] = "pawprint.fill",
        ["people"] = "person.2.fill",
        ["pizza"] = "fork.knife.circle.fill",
        ["planet"] = "globe.americas.fill",
        ["present"] = "gift.fill",
        ["rocket"] = "paperplane.fill",
        ["school"] = "graduationcap.fill",
        ["shapes"] = "square.on.circle.fill",
        ["shirt"] = "tshirt.fill",
        ["skull"] = "exclamationmark.octagon.fill",
        ["square"] = "square.fill",
        ["squares"] = "square.on.square.fill",
        ["star"] = "star.fill",
        ["star-1"] = "star.circle.fill",
        ["stats-chart"] = "chart.bar.fill",
        ["sun"] = "sun.max.fill",
        ["tada"] = "party.popper.fill",
        ["terminal"] = "terminal.fill",
        ["ticket"] = "ticket.fill",
        ["time"] = "clock.fill",
        ["trash"] = "trash.fill",
        ["triangle"] = "triangle.fill",
        ["video"] = "video.fill",
        ["volume-high"] = "speaker.wave.3.fill",
        ["wallet"] = "wallet.pass.fill",
        ["warning"] = "exclamationmark.triangle.fill",
        ["water"] = "drop.fill",
        ["weight"] = "dumbbell.fill"
    };
    private const string UntitledFolder = "Untitled Folder";
    private const double DefaultOpacity = 0.65;

    #endregion

    #region Types

    /// One of Zen's `folders`: a folder of a Space's pinned tabs, or a split
    /// view inside one, which names no Space.
    private sealed record Group(string Id, string? Name, string? ParentId, string? Workspace, bool IsSplit);

    #endregion

    #region Actions - Reading

    /// The Spaces the session holds, in order, however many: those past the
    /// most a workspace holds with their names alone, which an import leaves
    /// out. Throws `Rejected` with `SessionUnrecognized` for a file that is
    /// not Zen's session, and `SessionOverLimits` for one larger than an
    /// import decodes.
    public static IReadOnlyList<SessionDraft> Read(byte[] contents, DateTimeOffset importedAt) {
        using var document = ImportJson.Parse(MozillaLz4.Decoded(contents)) ?? throw new Rejected(new SessionUnrecognized());
        var root = ImportJson.Object(document.RootElement) ?? throw new Rejected(new SessionUnrecognized());
        var spaces = ImportJson.Array(ImportJson.Member(root, "spaces"));
        var tabs = ImportJson.Array(ImportJson.Member(root, "tabs"));
        if (spaces is null || tabs is null || spaces.Count == 0) throw new Rejected(new SessionUnrecognized());
        var all = (ImportJson.Array(ImportJson.Member(root, "folders")) ?? []).Select(Folder).OfType<Group>().ToArray();
        Dictionary<string, Group> groups = new(StringComparer.Ordinal);
        foreach (var group in all) groups.TryAdd(group.Id, group);
        var splits = Splits(root, all);
        // An Essential no Space claims is pinned in every Space.
        var owned = tabs.Where(tab => ImportJson.Object(tab) is not null).Select(tab => (Tab: tab,
            Owner: ImportJson.Text(ImportJson.Member(tab, "zenWorkspace")),
            Essential: ImportJson.Flag(ImportJson.Member(tab, "zenEssential")) ?? false)).ToArray();

        List<SessionDraft> drafts = [];
        for (int index = 0; index < spaces.Count; index++) {
            var space = spaces[index];
            if (ImportJson.Object(space) is null || ImportJson.Text(ImportJson.Member(space, "uuid")) is not { } workspace) continue;
            string name = ImportJson.Text(ImportJson.Member(space, "name")) ?? $"Zen Space {index + 1}";
            if (drafts.Count >= BrowserDataFile.MaximumSpaces) {
                drafts.Add(new SessionDraft(index + 1, name, [], []));
                continue;
            }
            var spaceGroups = all.Where(group => !group.IsSplit && group.Workspace == workspace).ToArray();
            HashSet<string> kept = [.. spaceGroups.Select(group => group.Id)];
            var spaceFolders = spaceGroups.Select(group => new SessionFolder(group.Id, group.Name ?? UntitledFolder,
                Holder(group.ParentId, groups, kept))).ToArray();
            List<SessionTab> spaceTabs = [];
            foreach (var (tab, owner, essential) in owned)
                if ((owner == workspace || (owner is null && essential))
                    && Tab(tab, Holder(ImportJson.Text(ImportJson.Member(tab, "groupId")), groups, kept), splits, importedAt) is { } decoded)
                    spaceTabs.Add(decoded);
            var theme = ImportJson.Member(space, "theme");
            var colors = Colors(theme);
            drafts.Add(new SessionDraft(index + 1, name, spaceFolders, spaceTabs, Icon(ImportJson.Text(ImportJson.Member(space, "icon"))),
                colors.Count == 0 ? SpaceAccent.Indigo : SpaceAccent.Nearest(colors[0]), Look(colors, theme)));
        }
        return drafts;
    }

    /// The group one of Zen's `folders` describes, spelled in either case,
    /// or null for one without an identity.
    private static Group? Folder(JsonElement folder) =>
        ImportJson.Object(folder) is null || ImportJson.Text(ImportJson.Member(folder, "id")) is not { } id ? null
            : new(id, ImportJson.Text(ImportJson.Member(folder, "name")),
                ImportJson.Text(ImportJson.Member(folder, "parentId")) ?? ImportJson.Text(ImportJson.Member(folder, "parentID")),
                ImportJson.Text(ImportJson.Member(folder, "workspaceId")) ?? ImportJson.Text(ImportJson.Member(folder, "workspaceID")),
                ImportJson.Flag(ImportJson.Member(folder, "splitViewGroup")) ?? false);

    /// The folder of a Space, among `kept`, that holds what names `group`:
    /// that folder, or the one holding the split view it names, or none for a
    /// split among the Space's pinned tabs or a group the Space does not keep.
    private static string? Holder(string? group, IReadOnlyDictionary<string, Group> groups, IReadOnlySet<string> kept) {
        for (int depth = 0; group is not null && depth <= groups.Count; depth++) {
            if (kept.Contains(group)) return group;
            group = groups.TryGetValue(group, out var split) && split.IsSplit ? split.ParentId : null;
        }
        return null;
    }

    /// The split views the session keeps, by identity: those `splitViewData`
    /// lists, the groups marked as one, and the folders that are one.
    private static HashSet<string> Splits(JsonElement root, IReadOnlyList<Group> folders) {
        HashSet<string> splits = new(StringComparer.Ordinal);
        foreach (var split in ImportJson.Array(ImportJson.Member(root, "splitViewData")) ?? [])
            if (ImportJson.Text(ImportJson.Member(split, "groupId")) is { } id) splits.Add(id);
        foreach (var group in ImportJson.Array(ImportJson.Member(root, "groups")) ?? [])
            if (ImportJson.Flag(ImportJson.Member(group, "splitView")) == true && ImportJson.Text(ImportJson.Member(group, "id")) is { } id)
                splits.Add(id);
        foreach (var folder in folders.Where(folder => folder.IsSplit)) splits.Add(folder.Id);
        return splits;
    }

    /// The page a tab shows: its selected history entry. Essentials are
    /// pinned tabs, and pinned tabs are saved tabs in `folder`. A tab in one
    /// of `splits` shows in that split.
    private static SessionTab? Tab(JsonElement tab, string? folder, IReadOnlySet<string> splits, DateTimeOffset importedAt) {
        if (ImportJson.Array(ImportJson.Member(tab, "entries")) is not { Count: > 0 } entries) return null;
        long selected = Math.Min(Math.Max(0, (ImportJson.Integer(ImportJson.Member(tab, "index")) ?? 1) - 1), entries.Count - 1);
        var entry = entries[(int)selected];
        if (ImportJson.Object(entry) is null || ImportJson.Text(ImportJson.Member(entry, "url")) is not { } url
            || ImportAddress.Read(url) is not { } address) return null;
        bool essential = ImportJson.Flag(ImportJson.Member(tab, "zenEssential")) ?? false;
        bool pinned = ImportJson.Flag(ImportJson.Member(tab, "pinned")) ?? false;
        var placement = essential ? TabPlacement.Pinned : pinned ? TabPlacement.Saved : TabPlacement.Current;
        var time = ImportJson.Number(ImportJson.Member(tab, "lastAccessed")) is { } raw ? ImportDate.FromUnixSecondsOrMilliseconds(raw) : null;
        string? split = ImportJson.Text(ImportJson.Member(tab, "groupId")) is { } group && splits.Contains(group) ? group : null;
        return new SessionTab(ImportJson.Text(ImportJson.Member(entry, "title")) ?? "", address, placement,
            placement == TabPlacement.Saved ? folder : null, time ?? importedAt, split);
    }

    #endregion

    #region Actions - Looks

    /// The SF Symbol for Zen's icon at `path`, the emoji the person chose, or
    /// Zen's own symbol for any other.
    private static string Icon(string? path) {
        if (path is null || path.Length == 0) return Symbol;
        int start = path.IndexOf(IconFolder, StringComparison.Ordinal);
        if (start < 0) return EmojiIcon.Chosen(path)?.Symbol ?? Symbol;
        string name = Path.GetFileNameWithoutExtension(path[(start + IconFolder.Length)..]);
        return IconSymbols.TryGetValue(name, out var symbol) ? symbol : Symbol;
    }

    /// The theme's gradient colors, spelled as hex, as components, or as Zen
    /// writes them, `c` holding red, green and blue from 0 to 255, at most as
    /// many as a look keeps.
    private static List<BrandColor> Colors(JsonElement? theme) {
        var values = ImportJson.Object(theme) is null ? null : ImportJson.Array(ImportJson.Member(theme, "gradientColors"));
        return [.. (values ?? []).Select(Color).OfType<BrandColor>().Take(SpaceBranding.MaximumColorCount)];
    }

    private static BrandColor? Color(JsonElement value) {
        if (ImportJson.Text(value) is { } hex) {
            string digits = hex.Trim('#');
            return digits.Length == 6 && int.TryParse(digits, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out int raw)
                ? new(((raw >> 16) & 0xFF) / 255.0, ((raw >> 8) & 0xFF) / 255.0, (raw & 0xFF) / 255.0) : null;
        }
        if (ImportJson.Array(ImportJson.Member(value, "c")) is { Count: 3 } components
            && components.Select(component => ImportJson.Number(component)).ToArray() is [{ } r, { } g, { } b])
            return new(Math.Clamp(r / ComponentScale, 0, 1), Math.Clamp(g / ComponentScale, 0, 1), Math.Clamp(b / ComponentScale, 0, 1));
        return ImportJson.Object(value) is not null && ImportJson.Number(ImportJson.Member(value, "red")) is { } red
            && ImportJson.Number(ImportJson.Member(value, "green")) is { } green
            && ImportJson.Number(ImportJson.Member(value, "blue")) is { } blue
            ? new(Math.Clamp(red, 0, 1), Math.Clamp(green, 0, 1), Math.Clamp(blue, 0, 1)) : null;
    }

    /// A gradient banner in bands of several colors, or a solid banner of
    /// one, as strong as the theme's opacity and textured as it is.
    private static SpaceBranding? Look(IReadOnlyList<BrandColor> colors, JsonElement? theme) => colors.Count == 0 ? null
        : SpaceBranding.Painted(colors, colors.Count > 1 ? SpaceBannerPattern.Bands : SpaceBannerPattern.Solid,
            Math.Clamp(ImportJson.Number(ImportJson.Member(theme, "opacity")) ?? DefaultOpacity, 0, 1), SpaceBranding.LegacyReadabilityFade,
            SpaceThemeMode.Gradient, gradientAngle: 45, showsTexture: (ImportJson.Integer(ImportJson.Member(theme, "texture")) ?? 0) != 0);

    #endregion
}
