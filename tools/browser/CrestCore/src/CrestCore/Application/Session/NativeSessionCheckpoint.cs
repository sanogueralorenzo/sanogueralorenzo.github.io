using System.Collections.Concurrent;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// An immutable, encodable revision of the session: the `core` part holds the
/// Spaces and their records without history, and each Space's history is its
/// own part, named by the Space's identity. Selection is window state, so no
/// part carries it. Storage writes these bytes; tests read them to see the
/// stored format.
internal sealed class NativeSessionCheckpoint {
    #region Variables

    internal const string CorePart = "core";

    private readonly SessionState session;
    private readonly ConcurrentDictionary<string, byte[]> parts = new();

    #endregion

    #region Constructors

    internal NativeSessionCheckpoint(SessionState session) => this.session = session;

    #endregion

    #region Actions - Checkpoint

    /// The part named `core`, or a Space's history named by its identity.
    public byte[] Read(string part) => parts.GetOrAdd(part, Encode);

    /// The session without history.
    internal byte[] Core() => Read(CorePart);

    /// One Space's history.
    internal byte[] History(Guid spaceId) => Read(spaceId.ToString());

    private byte[] Encode(string part) {
        JsonNode value = part == CorePart
            ? StoredSessionCodec.Encode(session with { Spaces = session.Spaces.Select(space => space with { History = [] }).ToArray() })
            : StoredSessionCodec.EncodeHistory(session.Spaces.Single(space => space.Id == Guid.Parse(part)).History);
        return Encoding.UTF8.GetBytes(value.ToJsonString());
    }

    #endregion
}
