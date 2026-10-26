using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The extensions a Chromium profile has installed from the Chrome Web Store,
/// read from the `extensions.settings` its `Secure Preferences` and
/// `Preferences` files keep for each extension, and from the extension's own
/// manifest for a name the settings do not spell out. Those turned off, built
/// in, loaded from a folder, or that are themes or apps are left out, as
/// Crest installs only what the Web Store gives it by identifier; so is one
/// that updates from another browser's store, whose identifiers are not the
/// Web Store's. Opera keeps its settings under `extensions.opsettings`.
internal static partial class ChromiumExtensions {
    #region Static Variables

    /// The most extensions one profile offers.
    public const int MaximumCount = 256;
    /// The largest settings or message file an import reads.
    private const long MaximumBytes = 50L * 1024 * 1024;
    private const long MaximumMessageBytes = 1024 * 1024;
    /// The largest icon an offer wears, in pixels: enough for a toolbar tile.
    private const int MaximumIconSize = 128;
    /// Chrome's `ManifestLocation::kInternal`, where it puts what the person
    /// installed from the Web Store.
    private const long InternalLocation = 1;
    private const string MessagePrefix = "__MSG_";
    private const string MessageSuffix = "__";

    /// The Web Store's update service, which a manifest the store served names.
    private const string WebStoreUpdateHost = "clients2.google.com";

    private static readonly string[] SettingsFiles = ["Preferences", "Secure Preferences"];
    private static readonly string[] SettingsKeys = ["settings", "opsettings"];
    private static readonly string[] FallbackLocales = ["en", "en_US", "en_GB"];

    #endregion

    #region Actions - Reading

    /// The Web Store extensions `profile` has installed and turned on, by
    /// name, an extension both settings files hold read as the last of them
    /// spells it.
    public static IReadOnlyList<ImportExtension> Read(ImportFolder profile) {
        Dictionary<string, JsonElement> settings = new(StringComparer.Ordinal);
        List<JsonDocument> documents = [];
        try {
            foreach (string name in SettingsFiles) {
                if (Document(profile, name) is not { } document) continue;
                documents.Add(document);
                var extensions = ImportJson.Member(document.RootElement, "extensions");
                foreach (string key in SettingsKeys)
                    foreach (var entry in ImportJson.Members(ImportJson.Member(extensions, key)))
                        if (IsIdentifier(entry.Name) && entry.Value.ValueKind == JsonValueKind.Object) settings[entry.Name] = entry.Value;
            }
            return [.. settings.Where(entry => IsWebStoreExtension(entry.Value))
                .Select(entry => Offer(profile, entry.Key, entry.Value)).OfType<ImportExtension>()
                .OrderBy(extension => extension.Name, StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(extension => extension.ExtensionId, StringComparer.Ordinal).Take(MaximumCount)];
        } finally {
            foreach (var document in documents) document.Dispose();
        }
    }

    /// A Web Store identifier: 32 letters from a to p.
    public static bool IsIdentifier(string value) => Identifier().IsMatch(value);

    /// Whether the settings describe an extension the person installed from
    /// the Web Store and has not turned off: an internal install flagged as
    /// from the store, not disabled, and neither a theme nor an app. Chromium
    /// has spelled "disabled" two ways: a `disable_reasons` list with any entry
    /// (the current form, which has no `state`), and an older `state` of zero
    /// or a `disable_reasons` bitmask above zero.
    private static bool IsWebStoreExtension(JsonElement settings) {
        if (ImportJson.Integer(ImportJson.Member(settings, "location")) != InternalLocation) return false;
        if (ImportJson.Flag(ImportJson.Member(settings, "from_webstore")) != true) return false;
        if (ImportJson.Integer(ImportJson.Member(settings, "state")) == 0) return false;
        if (HasDisableReasons(ImportJson.Member(settings, "disable_reasons"))) return false;
        var manifest = ImportJson.Member(settings, "manifest");
        return ImportJson.Member(manifest, "theme") is null && ImportJson.Member(manifest, "app") is null;
    }

    /// Whether `value` names a reason the extension is turned off: a list with
    /// any entry, or a number above zero.
    private static bool HasDisableReasons(JsonElement? value) =>
        ImportJson.Array(value) is { Count: > 0 } || ImportJson.Integer(value) is > 0;

    #endregion

    #region Actions - Offers

    /// The extension `id` offers, as its settings and its installed folder
    /// describe it, or null for one another store serves. The settings keep a
    /// copy of the manifest that may leave out what the extension's own
    /// manifest file says.
    private static ImportExtension? Offer(ImportFolder profile, string id, JsonElement settings) {
        var manifest = ImportJson.Member(settings, "manifest");
        var folder = Installed(profile, id, ImportJson.Text(ImportJson.Member(manifest, "version")));
        using var stored = folder is { } installed ? Read(installed, "manifest.json", MaximumMessageBytes) : null;
        var file = stored?.RootElement;
        if (!UpdatesFromWebStore(manifest, file)) return null;
        return new(id, Name(folder, id, manifest, file), folder is { } kept ? Icon(kept, manifest, file) : null);
    }

    /// Whether the manifest names the Web Store's update service, or none: a
    /// browser with its own store, as Edge has, marks what it installs from
    /// there as from its store too.
    private static bool UpdatesFromWebStore(JsonElement? manifest, JsonElement? stored) =>
        (ImportJson.Text(ImportJson.Member(manifest, "update_url")) ?? ImportJson.Text(ImportJson.Member(stored, "update_url"))) is not { } url
        || (Uri.TryCreate(url, UriKind.Absolute, out var address)
            && string.Equals(address.Host, WebStoreUpdateHost, StringComparison.OrdinalIgnoreCase));

    /// The name `id` shows: its manifest's, with a message in the manifest's
    /// own language, or `id` itself when nothing names it.
    private static string Name(ImportFolder? folder, string id, JsonElement? manifest, JsonElement? stored) {
        string? name = ImportJson.Text(ImportJson.Member(manifest, "name")) ?? ImportJson.Text(ImportJson.Member(stored, "name"));
        string? locale = ImportJson.Text(ImportJson.Member(manifest, "default_locale"))
            ?? ImportJson.Text(ImportJson.Member(stored, "default_locale"));
        if (name is not null && Message(name) is { } key) name = folder is { } installed ? Localized(installed, locale, key) : null;
        return name?.Trim() is { Length: > 0 } trimmed ? trimmed : id;
    }

    /// The key of `__MSG_key__`, or null for any other text.
    private static string? Message(string text) =>
        text.Length > MessagePrefix.Length + MessageSuffix.Length && text.StartsWith(MessagePrefix, StringComparison.Ordinal)
            && text.EndsWith(MessageSuffix, StringComparison.Ordinal) ? text[MessagePrefix.Length..^MessageSuffix.Length] : null;

    /// What the message `key` says in `locale`, the extension's default
    /// language, or in English, or null when its files do not say.
    private static string? Localized(ImportFolder folder, string? locale, string key) {
        List<string> locales = [];
        if (locale is not null) locales.Add(locale);
        locales.AddRange(FallbackLocales);
        foreach (string candidate in locales.Distinct(StringComparer.Ordinal)) {
            if (IsUnsafe(candidate)) continue;
            using var messages = Read(folder.Child("_locales").Child(candidate), "messages.json", MaximumMessageBytes);
            if (messages is null) continue;
            foreach (var entry in ImportJson.Members(messages.RootElement))
                if (string.Equals(entry.Name, key, StringComparison.OrdinalIgnoreCase)
                    && ImportJson.Text(ImportJson.Member(entry.Value, "message")) is { } message) return message;
        }
        return null;
    }

    /// The largest icon up to `MaximumIconSize` pixels the manifest lists that
    /// is a file inside `folder`, or null when it lists none.
    private static string? Icon(ImportFolder folder, JsonElement? manifest, JsonElement? stored) {
        var icons = ImportJson.Object(ImportJson.Member(manifest, "icons")) ?? ImportJson.Object(ImportJson.Member(stored, "icons"));
        return ImportJson.Members(icons)
            .Select(entry => (Size: int.TryParse(entry.Name, NumberStyles.None, CultureInfo.InvariantCulture, out int size) ? size : 0,
                Path: ImportJson.Text(entry.Value)))
            .Where(icon => icon.Size is > 0 and <= MaximumIconSize && icon.Path is { Length: > 0 })
            .OrderByDescending(icon => icon.Size)
            .Select(icon => Within(folder, icon.Path!))
            .FirstOrDefault(path => path is not null);
    }

    #endregion

    #region Actions - Files

    /// The folder holding `version` of `id`, or its last version when
    /// `version` is unknown. Chrome appends `_0` to a version it has seen
    /// before, which the settings leave out.
    private static ImportFolder? Installed(ImportFolder profile, string id, string? version) {
        var versions = profile.Child("Extensions").Child(id).Folders();
        if (version is not null && !IsUnsafe(version))
            foreach (var folder in versions)
                if (folder.Name == version || folder.Name.StartsWith(version + "_", StringComparison.Ordinal)) return folder;
        return versions.Count > 0 ? versions[^1] : null;
    }

    /// Whether `name` could leave the folder it is looked up in.
    private static bool IsUnsafe(string name) =>
        name.Contains('/') || name.Contains('\\') || name.Contains("..", StringComparison.Ordinal);

    /// The file `relative` names inside `folder`, where it is one there.
    private static string? Within(ImportFolder folder, string relative) {
        string[] parts = relative.Split('/', '\\', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || parts.Any(part => part == "..")) return null;
        string root = Path.GetFullPath(folder.Path);
        string path = Path.GetFullPath(Path.Combine([root, .. parts]));
        return path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal) && File.Exists(path) ? path : null;
    }

    private static JsonDocument? Document(ImportFolder profile, string name) => Read(profile, name, MaximumBytes);

    /// The JSON file `name` in `folder`, when it is small enough and is JSON.
    private static JsonDocument? Read(ImportFolder folder, string name, long maximum) {
        if (folder.File(name) is not { } path) return null;
        try {
            return new FileInfo(path).Length > maximum ? null : ImportJson.Parse(File.ReadAllBytes(path));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return null;
        }
    }

    [GeneratedRegex("^[a-p]{32}$", RegexOptions.CultureInvariant)]
    private static partial Regex Identifier();

    #endregion
}
