using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The unfinished manual setup earlier releases saved under
/// `BrowserManualSetupDraft`, which the device store adopts once: a JSON
/// object whose `spaces` each hold an identity stored bare or as
/// `{"rawValue": UUID}`, a `profile` with its `id`, `isNew`, and a
/// `customization` of `name`, `symbol`, `accent` by `Name` and `branding` as
/// the stored session spells it, with `spaceOrderWasEdited` when the order was
/// edited. The tabs a draft added are left out: no release offered a way to
/// add them.
internal static class LegacySetupDraftDocument {
    #region Static Variables

    private const string Spaces = "spaces";
    private const string OrderWasEdited = "spaceOrderWasEdited";
    private const string Id = "id";
    private const string Profile = "profile";
    private const string IsNew = "isNew";
    private const string Customization = "customization";
    private const string Name = "name";
    private const string Symbol = "symbol";
    private const string Accent = "accent";
    private const string Branding = "branding";

    private static readonly JsonDocumentOptions Options = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Adoption

    /// The setup `document` holds, or null when there is none or it does not
    /// read, as the release that saved it dropped a draft it could not read.
    public static KeptSetupDraft? Read(byte[]? document) {
        if (document is null || document.Length == 0) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: Options) is not JsonObject root || root[Spaces] is not JsonArray spaces) return null;
            var read = new List<SetupDraftSpace>();
            foreach (var node in spaces) {
                if (node is not JsonObject space || space[Profile] is not JsonObject profile || space[Customization] is not JsonObject chosen
                    || Flag(space[IsNew]) is not { } isNew || Text(chosen[Name]) is not { } name || Text(chosen[Symbol]) is not { } symbol
                    || SpaceAccent.Named(Text(chosen[Accent])) is not { } accent) return null;
                read.Add(new(StoredSessionCodec.Identity(space[Id]), StoredSessionCodec.Identity(profile[Id]), isNew,
                    new(name, symbol, accent, SpaceBranding.Normalized(chosen[Branding] is JsonObject branding
                        ? StoredSessionCodec.DecodeBranding(branding) : accent.House))));
            }
            return read.Count == 0 ? null : new(read, Flag(root[OrderWasEdited]) ?? false);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or BrowserRuleException) {
            return null;
        }
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    private static bool? Flag(JsonNode? node) => node is JsonValue value && value.TryGetValue(out bool flag) ? flag : null;

    #endregion
}
