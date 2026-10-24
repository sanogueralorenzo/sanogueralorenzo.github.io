using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial class InstalledBrowser {
    #region Static Variables

    /// How deep below Application Support a browser's data may sit, as
    /// `Vendor/Product/User Data` does.
    private const int SearchDepth = 3;
    /// The most folders a search looks into.
    private const int MaximumSearchedFolders = 4_000;
    /// The shortest name a folder may share only the start of with an app.
    private const int MinimumSharedName = 4;
    private const string ChromiumLocalState = "Local State";

    #endregion

    #region Actions - Searching

    /// The apps among `apps` that keep Chromium's data below `home`'s
    /// Application Support outside the folders of the browsers setup lists,
    /// each paired with the folder whose name names it best: one spelled as
    /// its bundle identifier, then one named as the app is, then one whose
    /// name starts as the app's does. Each folder goes to one app, the one it
    /// names best, and a folder keeping no profile goes to none.
    public static IReadOnlyList<ImportFoundBrowser> FindUnlisted(string home, IReadOnlyList<ImportBrowserApp> apps) {
        ArgumentNullException.ThrowIfNull(home);
        ArgumentNullException.ThrowIfNull(apps);
        var support = new ImportFolder(Path.Combine(home, "Library", "Application Support"));
        var listed = ImportSource.All.Where(source => source.IsListed)
            .Select(source => FullPath(Path.Combine(home, source.DataFolder))).OfType<string>().ToArray();
        var folders = ChromiumDataFolders(support)
            .Where(folder => FullPath(folder.Path) is { } path && !listed.Any(other => IsWithin(path, other) || IsWithin(other, path)))
            .Select(folder => (Folder: folder, Profiles: ChromiumProfiles(folder)))
            .Where(found => found.Profiles.Count > 0).ToArray();
        var pairs = apps.SelectMany(app => folders.Select(found => (App: app, found.Folder, found.Profiles,
                Score: Resemblance(app, Path.GetRelativePath(support.Path, found.Folder.Path)))))
            .Where(pair => pair.Score > 0)
            .OrderByDescending(pair => pair.Score).ThenByDescending(pair => ImportFolder.Changed(Path.Combine(pair.Folder.Path, ChromiumLocalState)));
        List<ImportFoundBrowser> found = [];
        HashSet<string> paired = new(StringComparer.Ordinal);
        foreach (var pair in pairs) {
            if (found.Any(browser => browser.BundleIdentifier == pair.App.BundleIdentifier) || !paired.Add(pair.Folder.Path)) continue;
            found.Add(new ImportFoundBrowser(pair.App.BundleIdentifier, pair.App.Name, pair.Folder.Path, new ImportData(pair.Profiles, [])));
        }
        return [.. found.OrderBy(browser => browser.Name, StringComparer.CurrentCultureIgnoreCase)];
    }

    /// The folders below `support` that hold a Chromium browser's data: a
    /// `Local State` beside its profiles, or beside the profile its folder is,
    /// as Opera keeps it. A browser's folder is not searched further.
    private static IReadOnlyList<ImportFolder> ChromiumDataFolders(ImportFolder support) {
        List<ImportFolder> found = [];
        Queue<(ImportFolder Folder, int Depth)> pending = new([(support, 0)]);
        int searched = 0;
        while (pending.TryDequeue(out var next) && searched++ < MaximumSearchedFolders) {
            if (next.Depth > 0 && IsChromiumData(next.Folder)) {
                found.Add(next.Folder);
                continue;
            }
            if (next.Depth < SearchDepth)
                foreach (var child in next.Folder.Folders()) pending.Enqueue((child, next.Depth + 1));
        }
        return found;
    }

    private static bool IsChromiumData(ImportFolder folder) =>
        folder.File(ChromiumLocalState) is not null && (folder.File(ChromiumPreferences) is not null
            || folder.Folders().Any(profile => IsChromiumProfile(profile.Name) && profile.File(ChromiumPreferences) is not null));

    /// How well the folder at `relative`, below Application Support, names
    /// `app`: 3 for a part spelled as its bundle identifier, 2 for one named as
    /// it is, 1 for one whose name starts as the app's, or the app's as its
    /// does, and 0 for none. Names compare by their letters and digits alone.
    private static int Resemblance(ImportBrowserApp app, string relative) {
        string name = Letters(app.Name);
        int best = 0;
        foreach (string part in relative.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries)) {
            string letters = Letters(part);
            int score = string.Equals(part, app.BundleIdentifier, StringComparison.OrdinalIgnoreCase) ? 3
                : name.Length > 0 && letters == name ? 2
                : Math.Min(letters.Length, name.Length) >= MinimumSharedName
                    && (letters.StartsWith(name, StringComparison.Ordinal) || name.StartsWith(letters, StringComparison.Ordinal)) ? 1
                : 0;
            best = Math.Max(best, score);
        }
        return best;
    }

    private static string Letters(string text) => new([.. text.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant)]);

    private static bool IsWithin(string path, string folder) =>
        path == folder || path.StartsWith(folder + Path.DirectorySeparatorChar, StringComparison.Ordinal);

    #endregion
}
