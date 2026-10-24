using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// What one synced record carries, typed: its payload, or its tombstone when
/// it was deleted, with every member this build does not know kept beside it
/// exactly as it arrived, so a newer build's fields survive this one.
internal sealed class SyncRecordBody {
    #region Static Variables

    /// The newest CloudKit schema this build reads and writes.
    public const int NewestSchema = 3;

    /// How deep a body may nest, as the journal reads it.
    private static readonly JsonDocumentOptions Document = new() { MaxDepth = 64 };

    /// How a body's bytes spell text: as UTF-8, as the Apple clients write it,
    /// escaping only what JSON requires.
    private static readonly JsonSerializerOptions Spelling = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    #endregion

    #region Variables

    /// The live record's payload, or null for a tombstone.
    public SyncPayload? Payload { get; }

    /// The deleted record's tombstone, or null for a live record.
    public SyncTombstone? Tombstone { get; }

    /// The members of the body this build does not know, as they arrived.
    private readonly JsonNode? additions;

    /// The oldest CloudKit schema whose clients read the record whole.
    public int Schema => Payload?.Schema ?? 1;

    #endregion

    #region Constructors

    private SyncRecordBody(SyncPayload? payload, SyncTombstone? tombstone, JsonNode? additions) {
        Payload = payload;
        Tombstone = tombstone;
        this.additions = additions;
    }

    #endregion

    #region Actions - Reading

    /// The body `bytes` hold as `form` spells it: a tombstone when
    /// `isTombstone`, else a payload. Throws `UnreadableSyncPayloadException`
    /// for one no client reads.
    public static SyncRecordBody Read(ReadOnlySpan<byte> bytes, bool isTombstone, SyncPayloadForm form) {
        JsonNode? node;
        try {
            node = JsonNode.Parse(bytes, documentOptions: Document);
        } catch (JsonException) {
            throw new UnreadableSyncPayloadException();
        }
        return Read(node, isTombstone, form);
    }

    /// The body `node` holds; see the overload.
    public static SyncRecordBody Read(JsonNode? node, bool isTombstone, SyncPayloadForm form) {
        if (node is not JsonObject body) throw new UnreadableSyncPayloadException();
        var payload = isTombstone ? null : SyncPayload.Decode(body, form);
        var tombstone = isTombstone ? SyncTombstone.Decode(body, form) : null;
        var known = payload?.Encode(SyncPayloadForm.Journal) ?? tombstone!.Encode(SyncPayloadForm.Journal);
        return new(payload, tombstone, Additions(body, known));
    }

    /// Throws `UnreadableSyncPayloadException` unless the body is what the
    /// record of `kind` with identity `id` in `space` may carry, and its
    /// payload keeps every rule clients check before they take one.
    public void RequireRecord(SyncRecordKind kind, Guid id, Guid space) {
        if (kind.NamesItsSpace && id != space) throw new UnreadableSyncPayloadException();
        if (Payload is not { } payload) return;
        if (payload.Kind != kind || payload.Id != id || payload.SpaceId != space) throw new UnreadableSyncPayloadException();
        payload.Validate();
    }

    /// Throws `UnreadableSyncPayloadException` unless this device may send the
    /// body as the record of `kind` with identity `id` in `space`: every client
    /// reads it, and it names no address this device cannot spell as they
    /// parse it.
    public void RequireSendable(SyncRecordKind kind, Guid id, Guid space) {
        RequireRecord(kind, id, space);
        Payload?.RequireSendable();
    }

    #endregion

    #region Actions - Writing

    /// The body as `form` spells it, with the members this build does not know.
    public JsonObject Write(SyncPayloadForm form) {
        var known = Payload?.Encode(form) ?? Tombstone!.Encode(form);
        var body = Adding(known, additions)!.AsObject();
        return form.SortsKeys ? Sorted(body)!.AsObject() : body;
    }

    /// The body's bytes as `form` spells it.
    public byte[] Bytes(SyncPayloadForm form) => Encoding.UTF8.GetBytes(Write(form).ToJsonString(Spelling));

    #endregion

    #region Actions - Additions

    /// What `source` holds that `known`, the same value as this build writes
    /// it, does not: every member it lacks, and inside the members both hold,
    /// what those lack. Members of a list follow their identity when they
    /// have one, their position otherwise. Null when there is nothing.
    private static JsonNode? Additions(JsonNode? source, JsonNode? known) {
        if (source is JsonObject fields && known is JsonObject knownFields) {
            var result = new JsonObject();
            foreach (var (key, value) in fields) {
                if (!knownFields.TryGetPropertyValue(key, out var recognized)) result[key] = value?.DeepClone();
                else if (Additions(value, recognized) is { } extra) result[key] = extra;
            }
            return result.Count == 0 ? null : result;
        }
        if (source is JsonArray items && known is JsonArray knownItems) {
            bool found = false;
            var result = new JsonArray();
            for (int index = 0; index < knownItems.Count; index++) {
                var element = knownItems[index];
                var original = Identity(element) is { } id ? items.FirstOrDefault(item => Identity(item) == id)
                    : index < items.Count ? items[index] : null;
                var extra = original is null ? null : Additions(original, element);
                found |= extra is not null;
                result.Add(extra ?? new JsonObject());
            }
            return found ? result : null;
        }
        return null;
    }

    /// `known` with `additions` laid over it: a member it lacks joins it, and
    /// inside the members both hold, what the additions hold joins it.
    private static JsonNode? Adding(JsonNode? known, JsonNode? additions) {
        if (additions is null) return known;
        if (known is JsonObject fields && additions is JsonObject extra) {
            var result = fields.DeepClone().AsObject();
            foreach (var (key, value) in extra)
                result[key] = result.TryGetPropertyValue(key, out var held) && held is not null ? Adding(held, value) : value?.DeepClone();
            return result;
        }
        if (known is JsonArray items && additions is JsonArray extraItems)
            return new JsonArray([.. items.Select((item, index) => index < extraItems.Count ? Adding(item, extraItems[index])?.DeepClone() : item?.DeepClone())]);
        return known?.DeepClone();
    }

    /// The identity a list member names, in lowercase, whether bare or
    /// wrapped as `{"rawValue": id}`.
    private static string? Identity(JsonNode? item) {
        var id = (item as JsonObject)?["id"];
        if (id is JsonObject wrapper) id = wrapper["rawValue"];
        return id is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>().ToLowerInvariant() : null;
    }

    /// `node` with every object's keys in ordinal order.
    private static JsonNode? Sorted(JsonNode? node) => node switch {
        JsonObject fields => new JsonObject(fields.OrderBy(field => field.Key, StringComparer.Ordinal)
            .Select(field => KeyValuePair.Create(field.Key, Sorted(field.Value)))),
        JsonArray items => new JsonArray([.. items.Select(Sorted)]),
        _ => node?.DeepClone()
    };

    #endregion
}
