using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The site-permission document earlier releases saved under
/// `crest.site-permissions.v1`, which the device store adopts once: a JSON
/// array of records whose identities are uppercase UUIDs, whose Space is
/// `{"rawValue": …}`, whose missing `detail` is the site-wide rule and whose
/// `modifiedAt` is seconds since 2001-01-01. A capability and a decision are
/// spelled as their set's `Name`. The origin and notification policies spell
/// an origin as a record does, `{"scheme": …, "host": …, "port": …}`.
internal static class SitePermissionDocument {
    #region Static Variables

    private const string Id = "id";
    private const string Space = "spaceID";
    private const string RawValue = "rawValue";
    private const string Origin = "origin";
    private const string Permission = "permission";
    private const string Detail = "detail";
    private const string Decision = "decision";
    private const string ModifiedAt = "modifiedAt";
    private const string Scheme = "scheme";
    private const string Host = "host";
    private const string Port = "port";

    #endregion

    #region Actions - Adoption

    /// Every record that still decodes, in document order. A document that is
    /// not JSON, or an entry this build cannot read, contributes nothing
    /// rather than failing the whole adoption.
    public static IReadOnlyList<SitePermissionRecord> Read(byte[]? document) {
        if (document is null || document.Length == 0) return [];
        JsonDocument parsed;
        try {
            parsed = JsonDocument.Parse(document, new() { MaxDepth = 8 });
        } catch (JsonException) {
            return [];
        }
        using (parsed) {
            if (parsed.RootElement.ValueKind != JsonValueKind.Array) return [];
            var records = new List<SitePermissionRecord>();
            foreach (var item in parsed.RootElement.EnumerateArray()) {
                if (records.Count >= SitePermissionLedger.MaximumRecords) break;
                if (Record(item) is { } record) records.Add(record);
            }
            return records;
        }
    }

    private static SitePermissionRecord? Record(JsonElement item) {
        try {
            if (item.ValueKind != JsonValueKind.Object) return null;
            var space = item.GetProperty(Space);
            var origin = item.GetProperty(Origin);
            if (SitePermission.Named(item.GetProperty(Permission).GetString()) is not { } permission
                || SitePermissionDecision.Named(item.GetProperty(Decision).GetString()) is not { } decision
                || Identity(item.GetProperty(Id)) is not { } id
                || Identity(space.ValueKind == JsonValueKind.Object ? space.GetProperty(RawValue) : space) is not { } spaceId)
                return null;
            string? detail = item.TryGetProperty(Detail, out var stored) && stored.ValueKind != JsonValueKind.Null ? stored.GetString() : null;
            var site = new SiteOrigin(origin.GetProperty(Scheme).GetString() ?? "", origin.GetProperty(Host).GetString() ?? "",
                origin.GetProperty(Port).GetInt32());
            return new(id, spaceId, site, permission, detail, decision, item.GetProperty(ModifiedAt).GetDouble());
        } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException) {
            return null;
        }
    }

    private static Guid? Identity(JsonElement value) =>
        value.ValueKind == JsonValueKind.String && Guid.TryParseExact(value.GetString(), "D", out var id) && id != Guid.Empty ? id : null;

    #endregion
}
