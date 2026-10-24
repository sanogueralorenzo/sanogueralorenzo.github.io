using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// An unfinished manual setup the device store keeps for the next launch, on
/// a platform that keeps one: its Spaces and whether its order was edited,
/// without the workspace, which a launch draws anew. The store keeps it as one
/// JSON document, `Document`, whose Spaces spell their identities bare, their
/// accent by `Name` and their look as the stored session does.
internal sealed record KeptSetupDraft(IReadOnlyList<SetupDraftSpace> Spaces, bool OrderWasEdited) {
    #region Static Variables

    private const string SpacesKey = "spaces";
    private const string OrderWasEditedKey = "orderWasEdited";
    private const string IdKey = "id";
    private const string ProfileKey = "profile";
    private const string IsNewKey = "isNew";
    private const string NameKey = "name";
    private const string SymbolKey = "symbol";
    private const string AccentKey = "accent";
    private const string BrandingKey = "branding";

    private static readonly JsonDocumentOptions Options = new() { MaxDepth = 32 };

    #endregion

    #region Variables

    /// The document the store keeps.
    public string Document => new JsonObject {
        [OrderWasEditedKey] = OrderWasEdited,
        [SpacesKey] = new JsonArray([.. Spaces.Select(space => (JsonNode)new JsonObject {
            [IdKey] = StoredSessionCodec.BareIdentity(space.SpaceId),
            [ProfileKey] = StoredSessionCodec.BareIdentity(space.ProfileId),
            [IsNewKey] = space.IsNew,
            [NameKey] = space.Customization.Name,
            [SymbolKey] = space.Customization.Symbol,
            [AccentKey] = space.Customization.Accent.Name,
            [BrandingKey] = StoredSessionCodec.Encode(space.Customization.Branding)
        })])
    }.ToJsonString();

    #endregion

    #region Actions - Keeping

    /// What the store keeps of `draft`.
    public static KeptSetupDraft From(SetupDraft draft) {
        ArgumentNullException.ThrowIfNull(draft);
        return new(draft.Spaces, draft.OrderWasEdited);
    }

    /// The setup this kept one resumes over the workspace `workspaceId`.
    public SetupDraft For(Guid workspaceId) => new(workspaceId, Spaces, OrderWasEdited);

    /// Whether `left` and `right` keep the same document.
    public static bool Same(KeptSetupDraft? left, KeptSetupDraft? right) => left?.Document == right?.Document;

    #endregion

    #region Actions - Reading

    /// The setup `document` keeps, or null when it does not read: a store
    /// written by this build always reads, so an unreadable one is dropped.
    public static KeptSetupDraft? Read(string? document) {
        if (string.IsNullOrEmpty(document)) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: Options) is not JsonObject root
                || root[SpacesKey] is not JsonArray spaces) return null;
            var read = new List<SetupDraftSpace>();
            foreach (var node in spaces) {
                if (node is not JsonObject space || Flag(space[IsNewKey]) is not { } isNew || Text(space[NameKey]) is not { } name
                    || Text(space[SymbolKey]) is not { } symbol || SpaceAccent.Named(Text(space[AccentKey])) is not { } accent) return null;
                read.Add(new(StoredSessionCodec.Identity(space[IdKey]), StoredSessionCodec.Identity(space[ProfileKey]), isNew,
                    new(name, symbol, accent, SpaceBranding.Normalized(StoredSessionCodec.DecodeBranding(space[BrandingKey])))));
            }
            return new(read, Flag(root[OrderWasEditedKey]) ?? false);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or BrowserRuleException) {
            return null;
        }
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    private static bool? Flag(JsonNode? node) => node is JsonValue value && value.TryGetValue(out bool flag) ? flag : null;

    #endregion
}
