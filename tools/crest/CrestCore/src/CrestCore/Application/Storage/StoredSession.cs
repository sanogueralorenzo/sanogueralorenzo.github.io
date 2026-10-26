using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// What a session file held when the core opened it: the session with each
/// Space's history, the sync journal when one was written, and the selection
/// an older release stored inside the session.
internal sealed record StoredSession(SessionState? Session, NativeSyncJournal? Journal, JsonObject? LegacySelection) {
    #region Variables

    private const string SchemaVersionField = "schemaVersion";
    private const int JournalSchemaVersion = 1;
    private static readonly JsonDocumentOptions DocumentOptions = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Decoding

    /// Decodes the parts one connection read. Throws `Rejected` when a part
    /// does not decode or was written by a newer release.
    public static StoredSession Decode(IReadOnlyDictionary<string, byte[]> parts) {
        try {
            return new(DecodeSession(parts, out var legacySelection), DecodeJournal(parts), legacySelection);
        } catch (Exception error) when (IsUndecodable(error)) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
    }

    /// Whether `error` is how a stored value that does not decode fails, as
    /// opposed to a rejection or a fault in the core.
    internal static bool IsUndecodable(Exception error) => error is BrowserRuleException or JsonException
        or InvalidOperationException or FormatException or KeyNotFoundException or ArgumentException or NullReferenceException;

    /// A sync journal on its own. Throws `Rejected` when it does not decode or
    /// was written by a newer release.
    internal static NativeSyncJournal DecodeJournal(ReadOnlySpan<byte> journal) {
        try {
            if (journal.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
            // The journal is read once: the version first, then the journal itself.
            var document = JsonNode.Parse(journal, documentOptions: DocumentOptions)!.AsObject();
            if (document[SchemaVersionField]!.GetValue<int>() > JournalSchemaVersion) throw new Rejected(new StorageFromNewerApp());
            return new NativeSyncJournal(document);
        } catch (Exception error) when (IsUndecodable(error)) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
    }

    private static SessionState? DecodeSession(IReadOnlyDictionary<string, byte[]> parts, out JsonObject? legacySelection) {
        legacySelection = null;
        if (!parts.TryGetValue(StoragePart.Core.Name, out var core)) return null;
        var document = JsonNode.Parse(core, documentOptions: DocumentOptions)!.AsObject();
        legacySelection = DecodeLegacySelection(document);
        var session = StoredSessionCodec.DecodeSession(document);
        return session with {
            Spaces = [.. session.Spaces.Select(space => space with { History = DecodeHistory(parts, space.Id) })]
        };
    }

    /// Every Space in the session part has its own history part; a session
    /// missing one is incomplete, never a Space without history.
    private static IReadOnlyList<HistoryEntryState> DecodeHistory(IReadOnlyDictionary<string, byte[]> parts, Guid spaceId) {
        if (!parts.TryGetValue(StoragePart.History(spaceId).Name, out var history))
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        return JsonNode.Parse(history, documentOptions: DocumentOptions)!.AsArray()
            .Select(StoredSessionCodec.DecodeHistoryEntry).ToArray();
    }

    private static NativeSyncJournal? DecodeJournal(IReadOnlyDictionary<string, byte[]> parts) =>
        parts.TryGetValue(StoragePart.Journal.Name, out var journal) ? DecodeJournal(journal) : null;

    /// The Space and per-Space tabs an older session part stored, kept so the
    /// first window without a record of its own can adopt them once.
    internal static JsonObject? DecodeLegacySelection(JsonObject document) {
        var spaces = document[StoredSessionCodec.Key.Spaces] as JsonArray ?? [];
        var tabs = spaces.OfType<JsonObject>()
            .Where(space => space[StoredSessionCodec.Key.LegacySelectedTab] is not null)
            .Select(space => (JsonNode?)new JsonObject {
                [StoredSessionCodec.Key.Id] = space[StoredSessionCodec.Key.Id]?.DeepClone(),
                [StoredSessionCodec.Key.LegacySelectedTab] = space[StoredSessionCodec.Key.LegacySelectedTab]!.DeepClone()
            }).ToArray();
        var selectedSpace = document[StoredSessionCodec.Key.LegacySelectedSpace];
        if (selectedSpace is null && tabs.Length == 0) return null;
        return new JsonObject {
            [StoredSessionCodec.Key.LegacySelectedSpace] = selectedSpace?.DeepClone(),
            [StoredSessionCodec.Key.Spaces] = new JsonArray(tabs)
        };
    }

    #endregion
}
