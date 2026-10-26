using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A Space's synced value: its identity and profile, how it looks and
/// browses, who may open it and when someone last chose, whether it uses
/// Crest Passwords once someone chose, its saved tabs' disclosure, its
/// splits' metadata and its position among the Spaces. Where it keeps its
/// passwords stays with each device.
internal sealed partial record SpacePayload(
    Guid Id,
    Guid ProfileId,
    string Name,
    string Symbol,
    SpaceAccent Accent,
    SpaceBranding Branding,
    BrowsingPreferences BrowsingPreferences,
    SpaceAccessPolicy AccessPolicy,
    SyncTime? AccessPolicyModifiedAt,
    bool? CredentialsEnabled,
    SyncTime? CredentialsEnabledModifiedAt,
    bool IsSavedTabsExpanded,
    SyncTime? SavedTabsExpansionModifiedAt,
    IReadOnlyList<SplitGroupPayload>? SplitGroups,
    string OrderToken) : SyncPayload {
    #region Static Variables

    /// The members a Space's value carries; a record keeps what a newer build
    /// writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.ProfileId, StoredSessionCodec.Key.Name, StoredSessionCodec.Key.Symbol,
        StoredSessionCodec.Key.Accent, StoredSessionCodec.Key.Branding, StoredSessionCodec.Key.BrowsingPreferences,
        StoredSessionCodec.Key.AccessPolicy, StoredSessionCodec.Key.AccessPolicyModifiedAt, SyncPayload.Key.CredentialsEnabled,
        StoredSessionCodec.Key.CredentialsEnabledModifiedAt, StoredSessionCodec.Key.IsSavedTabsExpanded,
        StoredSessionCodec.Key.SavedTabsExpansionModifiedAt, StoredSessionCodec.Key.SplitGroups, SyncPayload.Key.OrderToken
    ];

    /// The most splits a Space's record names.
    private const int MaximumSplitGroups = 5_000;

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;
    public override SyncRecordKind Kind => SyncRecordKind.Space;

    public override Guid SpaceId => Id;

    #endregion

    #region Actions - Coding

    /// The Space `value` holds. A Space without branding wears the branding its
    /// accent and symbol gave it before brandings synced; one without browsing
    /// preferences or an access policy takes the defaults; one without a saved
    /// tabs disclosure shows them; and one without splits' metadata, or without
    /// the time someone chose its lock or whether it uses Crest Passwords, holds
    /// no opinion about them.
    public static SpacePayload Read(SyncPayloadReader value) {
        string name = value.Text(StoredSessionCodec.Key.Name), symbol = value.Text(StoredSessionCodec.Key.Symbol);
        var accent = SpaceAccent.Named(value.Text(StoredSessionCodec.Key.Accent)) ?? throw new UnreadableSyncPayloadException();
        var (credentialsEnabled, credentialsModifiedAt) = value.OptionalFlag(Key.CredentialsEnabled) is { } enabled
            && value.OptionalTime(StoredSessionCodec.Key.CredentialsEnabledModifiedAt) is { } modifiedAt
                ? (enabled, modifiedAt) : ((bool?)null, (SyncTime?)null);
        return new(value.WrappedIdentity(StoredSessionCodec.Key.Id), value.Identity(StoredSessionCodec.Key.ProfileId), name, symbol, accent,
            value.OptionalNested(StoredSessionCodec.Key.Branding) is { } branding ? ReadBranding(branding) : SpaceBranding.Legacy(accent, symbol),
            value.OptionalNested(StoredSessionCodec.Key.BrowsingPreferences) is { } browsing ? ReadBrowsingPreferences(browsing)
                : StoredSessionCodec.DefaultBrowsingPreferences,
            value.OptionalText(StoredSessionCodec.Key.AccessPolicy) is { } access
                ? StoredSessionCodec.ParseAccessPolicy(access) ?? throw new UnreadableSyncPayloadException() : SpaceAccessPolicy.Open,
            value.OptionalTime(StoredSessionCodec.Key.AccessPolicyModifiedAt),
            credentialsEnabled,
            credentialsModifiedAt,
            value.OptionalFlag(StoredSessionCodec.Key.IsSavedTabsExpanded) ?? true,
            value.OptionalTime(StoredSessionCodec.Key.SavedTabsExpansionModifiedAt),
            value.OptionalArray(StoredSessionCodec.Key.SplitGroups) is { } groups ? SplitGroupPayload.Normalized(groups, value.Form) : null,
            value.Text(Key.OrderToken));
    }

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            [StoredSessionCodec.Key.Id] = StoredSessionCodec.WrappedIdentity(Id),
            [StoredSessionCodec.Key.ProfileId] = StoredSessionCodec.BareIdentity(ProfileId),
            [StoredSessionCodec.Key.Name] = Name,
            [StoredSessionCodec.Key.Symbol] = Symbol,
            [StoredSessionCodec.Key.Accent] = Accent.Name,
            [StoredSessionCodec.Key.Branding] = EncodeBranding(Branding),
            [StoredSessionCodec.Key.BrowsingPreferences] = StoredSessionCodec.Encode(BrowsingPreferences),
            [StoredSessionCodec.Key.AccessPolicy] = StoredSessionCodec.SpaceAccessPolicies.Name(AccessPolicy),
            [StoredSessionCodec.Key.IsSavedTabsExpanded] = IsSavedTabsExpanded
        };
        Put(value, StoredSessionCodec.Key.AccessPolicyModifiedAt, AccessPolicyModifiedAt, form);
        Put(value, StoredSessionCodec.Key.SavedTabsExpansionModifiedAt, SavedTabsExpansionModifiedAt, form);
        if (CredentialsEnabled is { } credentialsEnabled && CredentialsEnabledModifiedAt is { } credentialsModifiedAt) {
            value[Key.CredentialsEnabled] = credentialsEnabled;
            Put(value, StoredSessionCodec.Key.CredentialsEnabledModifiedAt, credentialsModifiedAt, form);
        }
        if (SplitGroups is { } groups)
            value[StoredSessionCodec.Key.SplitGroups] = new JsonArray([.. groups.Select(group => (JsonNode?)group.Encode(form))]);
        value[Key.OrderToken] = OrderToken;
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireText(Name, SyncedText.SpaceName.Limit);
        RequireText(Symbol, SyncedText.SpaceSymbol.Limit);
        if (SplitGroups is { } groups) {
            if (groups.Count > MaximumSplitGroups || groups.Select(group => group.Id).Distinct().Count() != groups.Count)
                throw new UnreadableSyncPayloadException();
            foreach (var group in groups) group.Validate();
        }
        RequireOrderToken(OrderToken);
    }

    #endregion
}
