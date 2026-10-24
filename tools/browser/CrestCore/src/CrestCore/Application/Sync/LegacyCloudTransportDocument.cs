using System.Text;
using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The cloud transport state an installed release kept in its own JSON file,
/// read as that release read it.
internal static class LegacyCloudTransportDocument {
    #region Static Variables

    /// The record schema a file that names none was written under.
    private const int FirstRecordSchema = 1;

    #endregion

    #region Actions - Reading

    /// The state `bytes` hold, and the server fields they keep, for a
    /// transport that reads and writes `recordSchema`. A file written under an
    /// older schema keeps its flags but leaves its cursor and fields behind. A
    /// pause for an account change is kept; the pause older builds kept for
    /// an ordinary record race, spelled as a bare `requiresAccountConfirmation`
    /// or as that reason, is dropped. Throws `Rejected` with
    /// `LegacyCloudStateUnreadable` when the file does not read as that
    /// release's did.
    public static (CloudTransportRecord Record, IReadOnlyList<CloudRecordFields> Fields) Read(byte[] bytes, int recordSchema) {
        ArgumentNullException.ThrowIfNull(bytes);
        try {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw Unreadable();
            bool requiresFullPull = Bool(root, "requiresFullPull") ?? false;
            int written = Int(root, "recordSchemaVersion") ?? FirstRecordSchema;
            bool current = written >= recordSchema;
            byte[]? engineState = current && root.TryGetProperty("engineStateSerialization", out var engine)
                && engine.ValueKind != JsonValueKind.Null
                ? Encoding.UTF8.GetBytes(engine.GetRawText()) : null;
            var fields = current ? Fields(root) : [];
            bool overwritesCloud = Text(root, "conflictResolution") switch {
                null => false,
                "useThisDevice" => true,
                _ => throw Unreadable()
            };
            string? reason = Text(root, "reconciliationReason");
            // Builds before the reason kept only a flag, which paused for an
            // ordinary record race and is dropped; it must still read.
            if (reason is null) _ = Bool(root, "requiresAccountConfirmation");
            bool awaitsAccountDecision = reason switch {
                null => false,
                "accountChange" => true,
                "legacyRecordConflict" => false,
                _ => throw Unreadable()
            };
            return (new(recordSchema, requiresFullPull, awaitsAccountDecision, overwritesCloud, engineState), fields);
        } catch (JsonException) {
            throw Unreadable();
        } catch (FormatException) {
            throw Unreadable();
        } catch (InvalidOperationException) {
            throw Unreadable();
        } catch (KeyNotFoundException) {
            throw Unreadable();
        }
    }

    /// Each record's archived server fields and the schema its server copy
    /// carries, in record name order. A file without fields keeps none; one
    /// whose fields lack their archives does not read.
    private static List<CloudRecordFields> Fields(JsonElement root) {
        if (!root.TryGetProperty("systemFields", out var system) || system.ValueKind == JsonValueKind.Null) return [];
        var archives = system.GetProperty("encodedRecordsByName");
        var schemas = new Dictionary<string, int>(StringComparer.Ordinal);
        if (system.TryGetProperty("schemaVersionsByName", out var versions) && versions.ValueKind != JsonValueKind.Null)
            foreach (var version in versions.EnumerateObject()) schemas[version.Name] = version.Value.GetInt32();
        return [.. archives.EnumerateObject().OrderBy(archive => archive.Name, StringComparer.Ordinal)
            .Select(archive => new CloudRecordFields(archive.Name, archive.Value.GetBytesFromBase64(),
                schemas.TryGetValue(archive.Name, out int schema) ? schema : null))];
    }

    private static bool? Bool(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetBoolean() : null;

    private static int? Int(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetInt32() : null;

    private static string? Text(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetString() : null;

    private static Rejected Unreadable() => new(new LegacyCloudStateUnreadable());

    #endregion
}
