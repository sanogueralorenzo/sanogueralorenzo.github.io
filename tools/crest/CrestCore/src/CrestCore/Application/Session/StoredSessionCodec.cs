using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>
/// The session's stored format, which Swift's Codable models defined: identities
/// wrapped as <c>{"rawValue": UUID}</c>, dates as seconds since 2001, absent optional
/// members, and the tolerant readings the native decoder applies. Checkpoints and the
/// session projections Swift reads are written here and nowhere else, and every stored
/// key and value spelling lives in this type. Members this format does not define are
/// not kept: Swift's own decoder drops them before any session reaches the core.
/// </summary>
internal static partial class StoredSessionCodec {
    #region Variables

    /// Seconds from 1970 to 2001, where the stored dates count from, as Apple
    /// platforms' dates do.
    internal const double ReferenceEpochUnixSeconds = 978_307_200;

    private static readonly DateTimeOffset ReferenceEpoch = DateTimeOffset.UnixEpoch.AddSeconds(ReferenceEpochUnixSeconds);

    /// The stored member names, shared by every record that uses one.
    internal static class Key {
        public const string AccessPolicy = "accessPolicy";
        public const string Accent = "accent";
        public const string AlsoOffersSaveToSystemPasswords = "alsoOffersSaveToSystemPasswords";
        public const string Alpha = "alpha";
        public const string AppPreferences = "appPreferences";
        public const string Archive = "archive";
        public const string ArchivedAt = "archivedAt";
        public const string ArchivedTabs = "archivedTabs";
        public const string AutomaticallyEntersPictureInPicture = "automaticallyEntersPictureInPicture";
        public const string AutomaticallyShowsDeveloperToolbar = "automaticallyShowsDeveloperToolbar";
        public const string AutomaticallyTranslates = "automaticallyTranslates";
        public const string Backplate = "backplate";
        public const string BackplateColorIndex = "backplateColorIndex";
        public const string BannerPattern = "bannerPattern";
        public const string BannerStrength = "bannerStrength";
        public const string Blue = "blue";
        public const string Branding = "branding";
        public const string BrowsingPreferences = "browsingPreferences";
        public const string Charge = "charge";
        public const string ChargeLayout = "chargeLayout";
        public const string ChargeWeight = "chargeWeight";
        public const string ChecksSpelling = "checksSpelling";
        public const string CollapseModifiedAt = "collapseModifiedAt";
        public const string Color = "color";
        public const string Colors = "colors";
        public const string CompletesInline = "completesInline";
        public const string ContentBlockingPolicy = "contentBlockingPolicy";
        public const string CredentialPreferences = "credentialPreferences";
        public const string Crest = "crest";
        public const string CurrentTabCleanupPolicy = "currentTabCleanupPolicy";
        public const string CustomIconSymbol = "customIconSymbol";
        public const string CustomSearchProviders = "customSearchProviders";
        public const string CustomTitle = "customTitle";
        public const string DataRetention = "dataRetention";
        public const string DefaultSpaceId = "defaultSpaceID";
        public const string DeletionOrigin = "deletionOrigin";
        public const string Depth = "depth";
        public const string DisposableSeedMarker = "disposableSeedMarker";
        public const string Downloads = "downloads";
        public const string EdgeColorIndex = "edgeColorIndex";
        public const string FaviconUrl = "faviconURL";
        public const string FieldDivision = "fieldDivision";
        public const string Finish = "finish";
        public const string FirstVisitedAt = "firstVisitedAt";
        public const string FolderColorIntensity = "folderColorIntensity";
        public const string FolderId = "folderID";
        public const string Folders = "folders";
        public const string GradientAngle = "gradientAngle";
        public const string Green = "green";
        public const string HasCustomAppearance = "hasCustomAppearance";
        public const string History = "history";
        public const string IconAccent = "iconAccent";
        public const string IconModifiedAt = "iconModifiedAt";
        public const string IconStyle = "iconStyle";
        public const string Id = "id";
        public const string IsCollapsed = "isCollapsed";
        public const string IsEnabled = "isEnabled";
        public const string IsSavedTabsExpanded = "isSavedTabsExpanded";
        public const string KeepsControlsReadable = "keepsControlsReadable";
        public const string KeepsPageLoaded = "keepsPageLoaded";
        public const string Kind = "kind";
        public const string LastActivatedAt = "lastActivatedAt";
        public const string LastVisitedAt = "lastVisitedAt";
        public const string Layout = "layout";
        public const string LearnsChoices = "learnsChoices";
        public const string LegacySearchProvider = "searchProvider";
        public const string LegacySelectedSpace = "selectedSpaceID";
        public const string LegacySelectedTab = "selectedTabID";
        public const string Limit = "limit";
        public const string Location = "location";
        public const string Name = "name";
        public const string NativeContent = "nativeContent";
        public const string OffersTranslation = "offersTranslation";
        public const string OperationId = "operationID";
        public const string OrderAnchorTabId = "orderAnchorTabID";
        public const string Ordinary = "ordinary";
        public const string OrdinaryColorIndex = "ordinaryColorIndex";
        public const string Palette = "palette";
        public const string ParentId = "parentID";
        public const string Placement = "placement";
        public const string PositionModifiedAt = "positionModifiedAt";
        public const string PrefersOpenTabs = "prefersOpenTabs";
        public const string ProviderSpaceTrigger = "providerSpaceTrigger";
        public const string Profile = "profile";
        public const string ProfileId = "profileID";
        public const string RawValue = "rawValue";
        public const string ReadabilityFade = "readabilityFade";
        public const string Reason = "reason";
        public const string Red = "red";
        public const string RenderingVersion = "renderingVersion";
        public const string ResourceId = "resourceID";
        public const string SavedTabClosePolicy = "savedTabClosePolicy";
        public const string SavedTabFaviconReturnsToSavedUrl = "savedTabFaviconReturnsToSavedURL";
        public const string SavedTabsExpansionModifiedAt = "savedTabsExpansionModifiedAt";
        public const string CredentialsEnabledModifiedAt = "credentialsEnabledModifiedAt";
        public const string AccessPolicyModifiedAt = "accessPolicyModifiedAt";
        public const string SavedUrl = "savedURL";
        public const string SearchesSitesWithTab = "searchesSitesWithTab";
        public const string SearchFollowsDefault = "searchFollowsDefault";
        public const string SearchSuggestionsEnabled = "searchSuggestionsEnabled";
        public const string SearchUrlTemplate = "searchURLTemplate";
        public const string SecondaryFieldColorIndex = "secondaryFieldColorIndex";
        public const string SelectedSearchProviderId = "selectedSearchProviderID";
        public const string ShowsOutline = "showsOutline";
        public const string ShowsReasons = "showsReasons";
        public const string ShowsRecentTabs = "showsRecentTabs";
        public const string ShowsTexture = "showsTexture";
        public const string ShowsTopHit = "showsTopHit";
        public const string Source = "source";
        public const string Sources = "sources";
        public const string SpaceDeletions = "spaceDeletions";
        public const string SpaceId = "spaceID";
        public const string Spaces = "spaces";
        public const string SplitFocusFollowsMouse = "splitFocusFollowsMouse";
        public const string SplitGroupId = "splitGroupID";
        public const string SplitGroups = "splitGroups";
        public const string StartingPresetId = "startingPresetID";
        public const string StartupBehavior = "startupBehavior";
        public const string StoredIconMode = "storedIconMode";
        public const string Style = "style";
        public const string SuggestionsFollowDefault = "suggestionsFollowDefault";
        public const string SuggestionUrlTemplate = "suggestionURLTemplate";
        public const string Symbol = "symbol";
        public const string SymbolColor = "symbolColor";
        public const string SymbolColorIndex = "symbolColorIndex";
        public const string SyncsCrestPasswordsWithICloud = "syncsCrestPasswordsWithICloud";
        public const string Tab = "tab";
        public const string Tabs = "tabs";
        public const string TargetId = "targetID";
        public const string TextColorMode = "textColorMode";
        public const string ThemeMode = "themeMode";
        public const string Tint = "tint";
        public const string TintModifiedAt = "tintModifiedAt";
        public const string Title = "title";
        public const string TitleModifiedAt = "titleModifiedAt";
        public const string TranslationRules = "translationRules";
        public const string Trim = "trim";
        public const string TrimColorIndex = "trimColorIndex";
        public const string Url = "url";
        public const string Value = "value";
        public const string VisitCount = "visitCount";
    }

    /// One closed set's stored spellings, read and written through the same pairs.
    /// A spelling this build does not know reads as null, for the caller's default.
    internal sealed class StoredSpellings<T>(IReadOnlyList<(T Value, string Spelling)> pairs) where T : struct, Enum {
        #region Variables

        private readonly Dictionary<string, T> values = pairs.ToDictionary(pair => pair.Spelling, pair => pair.Value, StringComparer.Ordinal);
        private readonly Dictionary<T, string> spellings = pairs.ToDictionary(pair => pair.Value, pair => pair.Spelling);

        #endregion

        #region Actions - Spelling

        public T? Parse(string? spelling) => spelling is not null && values.TryGetValue(spelling, out var value) ? value : null;

        public string Name(T value) => spellings[value];

        #endregion
    }

    #endregion

    #region Actions - Identities

    /// An identity stored bare or wrapped the way Swift codes its typed IDs. An
    /// empty identity reads as itself: checkpoint repair replaces it, and the
    /// session authority refuses a Space, profile or tab that has one.
    internal static Guid Identity(JsonNode? node) {
        if (node is JsonObject wrapped) node = wrapped[Key.RawValue];
        return Guid.TryParse(Text(node), out var id) ? id : throw new BrowserRuleException(BrowserRule.InvalidSavedIdentity);
    }

    internal static Guid? OptionalIdentity(JsonNode? node) => node is null ? null : Identity(node);

    /// Swift's spelling of a UUID.
    internal static JsonValue BareIdentity(Guid id) => JsonValue.Create(id.ToString("D").ToUpperInvariant());

    /// A typed Swift identity: `{"rawValue": UUID}`.
    internal static JsonObject WrappedIdentity(Guid id) => new() { [Key.RawValue] = BareIdentity(id) };

    #endregion

    #region Actions - Dates

    /// Seconds since 2001, to the nearest tick. Every date after 2018 and every
    /// value with at most seven fractional digits comes back as the same double.
    /// A date outside years 1 through 9999, such as Swift's `distantPast`, reads
    /// as the nearest one a `DateTimeOffset` holds.
    internal static DateTimeOffset Date(double seconds) {
        if (!double.IsFinite(seconds)) throw new BrowserRuleException(BrowserRule.InvalidSavedDate);
        if (seconds <= Seconds(DateTimeOffset.MinValue)) return DateTimeOffset.MinValue;
        if (seconds >= Seconds(DateTimeOffset.MaxValue)) return DateTimeOffset.MaxValue;
        double whole = Math.Floor(seconds);
        long ticks = (long)whole * TimeSpan.TicksPerSecond
            + (long)Math.Round((seconds - whole) * TimeSpan.TicksPerSecond, MidpointRounding.AwayFromZero);
        return ticks >= (DateTimeOffset.MaxValue - ReferenceEpoch).Ticks ? DateTimeOffset.MaxValue : ReferenceEpoch.AddTicks(ticks);
    }

    internal static double Seconds(DateTimeOffset date) {
        long whole = Math.DivRem((date - ReferenceEpoch).Ticks, TimeSpan.TicksPerSecond, out long remainder);
        return whole + remainder / (double)TimeSpan.TicksPerSecond;
    }

    /// An edit clock. One the domain wrote is whole milliseconds and takes Swift's
    /// own arithmetic, so both sides agree to the bit and repair cannot invent an
    /// edit; any other stored value goes back exactly as it came.
    private static double EditSeconds(DateTimeOffset date) =>
        (date - DateTimeOffset.UnixEpoch).Ticks % TimeSpan.TicksPerMillisecond == 0 ? NativeEditTimestamp.Encode(date) : Seconds(date);

    private static DateTimeOffset Date(JsonNode? node) => node is null ? ReferenceEpoch : Date(Number(node));

    private static DateTimeOffset? OptionalDate(JsonNode? node) => node is null ? null : Date(Number(node));

    #endregion

    #region Actions - Values

    private static JsonObject Object(JsonNode? node) =>
        node as JsonObject ?? throw new BrowserRuleException(BrowserRule.InvalidSavedState);

    private static JsonArray Items(JsonNode? node) =>
        node is null ? [] : node as JsonArray ?? throw new BrowserRuleException(BrowserRule.InvalidSavedState);

    internal static string? Text(JsonNode? node) => node is null ? null : node.GetValue<string>();

    private static bool? Flag(JsonNode? node) => node?.GetValue<bool>();

    /// A flag that reads as absent when it holds anything but a boolean.
    private static bool? TolerantFlag(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() is JsonValueKind.True or JsonValueKind.False ? value.GetValue<bool>() : null;

    /// Text that reads as absent when it holds anything but a string.
    private static string? TolerantText(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null;

    /// A number parsed from JSON or placed in a node by code.
    private static double Number(JsonNode node) {
        if (node is JsonValue value) {
            if (value.TryGetValue(out double number)) return number;
            if (value.TryGetValue(out long whole)) return whole;
            if (value.TryGetValue(out int small)) return small;
            if (value.TryGetValue(out decimal exact)) return (double)exact;
        }
        throw new BrowserRuleException(BrowserRule.InvalidSavedState);
    }

    private static double? OptionalNumber(JsonNode? node) => node is null ? null : Number(node);

    private static int? Integer(JsonNode? node) {
        if (node is null) return null;
        double number = Number(node);
        return number == Math.Floor(number) && number is >= int.MinValue and <= int.MaxValue
            ? (int)number : throw new BrowserRuleException(BrowserRule.InvalidSavedState);
    }

    private static void Put(JsonObject value, string key, string? member) {
        if (member is not null) value[key] = member;
    }

    private static void Put(JsonObject value, string key, bool? member) {
        if (member is { } flag) value[key] = flag;
    }

    private static void Put(JsonObject value, string key, DateTimeOffset? member) {
        if (member is { } date) value[key] = Seconds(date);
    }

    private static void PutEdit(JsonObject value, string key, DateTimeOffset? member) {
        if (member is { } date) value[key] = EditSeconds(date);
    }

    #endregion
}
