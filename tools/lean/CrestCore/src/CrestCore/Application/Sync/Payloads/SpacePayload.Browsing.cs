using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Actions - Browsing preferences

    private static BrowsingPreferences ReadBrowsingPreferences(SyncPayloadReader value) {
        var blocking = value.OptionalNamed(StoredSessionCodec.Key.ContentBlockingPolicy, ContentBlockingPolicy.Named) ?? ContentBlockingPolicy.Balanced;
        var retention = value.OptionalNested(StoredSessionCodec.Key.DataRetention) is { } kept
            ? new DataRetentionPreferences(kept.Named(StoredSessionCodec.Key.History, DataRetention.Named),
                kept.Named(StoredSessionCodec.Key.Archive, DataRetention.Named), kept.Named(StoredSessionCodec.Key.Downloads, DataRetention.Named))
            : StoredSessionCodec.DefaultBrowsingPreferences.DataRetention;
        return new(blocking, retention);
    }

    #endregion
}
