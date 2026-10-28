using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Crest's own browser-data file, which an export writes and an import reads
/// back: a JSON document naming its format and schema version, with each
/// Space as `BrowserDataSpace` keeps it and times in milliseconds since 1970.
/// Its keys are written sorted and indented, and reading accepts every schema
/// version since the first.
internal static class BrowserDataFile {
    #region Static Variables

    public const string Format = "com.pauldavis.crest.browser-data";
    public const int SchemaVersion = 5;
    /// The largest file an import reads or an export writes.
    public const int MaximumBytes = 50 * 1024 * 1024;
    /// The most Spaces a file holds.
    public const int MaximumSpaces = 64;

    private static readonly JsonDocumentOptions Document = new() { MaxDepth = 64 };
    private static readonly JsonWriterOptions Writer = new() {
        Indented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        SkipValidation = false
    };

    #endregion

    #region Actions - Reading

    /// The Spaces `contents` holds, as a file keeps them. Throws `Rejected`
    /// with `ArchiveTooLarge`, `NotAnArchive`, `UnsupportedArchiveVersion` or
    /// `ArchiveInvalid`.
    public static IReadOnlyList<BrowserDataSpace> Read(ReadOnlySpan<byte> contents) {
        if (contents.Length > MaximumBytes) throw new Rejected(new ArchiveTooLarge());
        JsonNode? root;
        try {
            root = JsonNode.Parse(contents, documentOptions: Document);
        } catch (JsonException) {
            throw BrowserDataValue.Invalid();
        }
        BrowserDataValue file;
        string format;
        int version;
        IReadOnlyList<BrowserDataSpace> spaces;
        try {
            file = BrowserDataValue.Of(root);
            format = file.Text("format");
            version = file.Integer("schemaVersion");
            _ = file.Date("exportedAt");
            spaces = [.. file.Items("spaces").Select(BrowserDataSpace.Read)];
        } catch (Exception error) when (error is InvalidOperationException or FormatException or BrowserRuleException) {
            throw BrowserDataValue.Invalid();
        }
        if (format != Format) throw new Rejected(new NotAnArchive());
        if (version is < 1 or > SchemaVersion) throw new Rejected(new UnsupportedArchiveVersion(version));
        if (spaces.Count is 0 or > MaximumSpaces) throw BrowserDataValue.Invalid();
        return spaces;
    }

    #endregion

    #region Actions - Writing

    /// The file of `spaces`, exported at `exportedAt`. Throws `Rejected` with
    /// `ArchiveTooLarge` when it would be larger than an import reads.
    public static byte[] Write(IEnumerable<BrowserDataSpace> spaces, DateTimeOffset exportedAt) {
        var root = new JsonObject {
            ["format"] = Format,
            ["schemaVersion"] = SchemaVersion,
            ["exportedAt"] = ImportDate.UnixMilliseconds(exportedAt),
            ["spaces"] = new JsonArray([.. spaces.Select(space => (JsonNode)space.Write())])
        };
        var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, Writer)) WriteSorted(writer, root);
        return buffer.Length > MaximumBytes ? throw new Rejected(new ArchiveTooLarge()) : buffer.ToArray();
    }

    /// An identity as the file spells it.
    public static JsonNode Identity(Guid id) => JsonValue.Create(id.ToString("D").ToUpperInvariant());

    /// A color as the file spells it.
    public static JsonObject Color(BrandColor color) {
        ArgumentNullException.ThrowIfNull(color);
        return new() { ["red"] = color.Red, ["green"] = color.Green, ["blue"] = color.Blue, ["alpha"] = color.Alpha };
    }

    /// `node` with every object's keys in order, as the Apple platforms'
    /// encoder sorts them.
    private static void WriteSorted(Utf8JsonWriter writer, JsonNode? node) {
        switch (node) {
            case JsonObject value:
                writer.WriteStartObject();
                foreach (var member in value.OrderBy(member => member.Key, StringComparer.Ordinal)) {
                    writer.WritePropertyName(member.Key);
                    WriteSorted(writer, member.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonArray items:
                writer.WriteStartArray();
                foreach (var item in items) WriteSorted(writer, item);
                writer.WriteEndArray();
                break;
            case null:
                writer.WriteNullValue();
                break;
            default:
                node.WriteTo(writer);
                break;
        }
    }

    #endregion
}
