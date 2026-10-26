using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The first session a file gets: the one the installed release kept in its
/// defaults, with the journal and the selection it kept, or the seed that
/// stands in when there is none to carry.
internal sealed record FirstSession(SessionState Session, NativeSyncJournal? Journal, JsonObject? LegacySelection,
    IReadOnlyList<TabFavicon> Favicons, bool RequestsCloudRecovery) {
    #region Variables

    private static readonly JsonDocumentOptions DocumentOptions = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Choosing

    /// The session `adoption` gives a file. The installed session is its
    /// history-free core with each Space's history beside it, or, before that
    /// split, one whole graph with history and images inside it. One that does
    /// not decode is left alone: the seed stands in, or without one
    /// `firstInstall`, and the cloud is asked for a full pull instead of
    /// learning that every real Space was deleted. The journal goes only with
    /// an installed session. Throws `Rejected` when that journal does not decode.
    public static FirstSession For(AdoptLegacySession adoption, Func<SessionState> firstInstall) {
        ArgumentNullException.ThrowIfNull(adoption);
        ArgumentNullException.ThrowIfNull(firstInstall);
        var installed = adoption.Installed;
        var seed = adoption.Seed ?? firstInstall();
        if (installed.Core is { } core) {
            var history = installed.History.ToDictionary(part => part.SpaceId, part => part.Entries);
            return Installed(core, installed.Journal, space => history.TryGetValue(space.Id, out var entries)
                ? StoredSessionCodec.DecodeInstalledHistory(entries) : []) ?? Seeded(seed, requestsCloudRecovery: true);
        }
        if (installed.WholeGraph is { } wholeGraph)
            return Installed(wholeGraph, installed.Journal, space => space.History) ?? Seeded(seed, requestsCloudRecovery: true);
        return Seeded(seed, requestsCloudRecovery: false);
    }

    /// The session a first launch starts with when nothing is carried to it:
    /// the first-install Space, marked as the disposable seed, with identities
    /// from `ids`, stamped at `now` as the session stores the time. See
    /// `FirstInstallSession`.
    public static SessionState FirstInstall(Func<Guid> ids, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(ids);
        var stamped = StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));
        var space = SpaceTemplate.FirstInstall.Make(ids(), ids(), ids, number: 1, stamped);
        return new([space], DefaultSpaceId: null, DisposableSeedMarker: ids(), SpaceDeletions: [], AppPreferences: null);
    }

    /// The installed session with each Space's history from `history`, or null
    /// when the bytes are not a session this build can read.
    private static FirstSession? Installed(byte[] bytes, byte[]? journal,
        Func<SpaceState, IReadOnlyList<HistoryEntryState>> history) {
        if (Decode(bytes) is not { } decoded) return null;
        var session = decoded.Session with {
            Spaces = [.. decoded.Session.Spaces.Select(space => space with { History = history(space) })]
        };
        return new(session, journal is null ? null : StoredSession.DecodeJournal(journal),
            StoredSession.DecodeLegacySelection(decoded.Document), decoded.Favicons, RequestsCloudRecovery: false);
    }

    /// A seed carries no images: the platform keeps its own.
    private static FirstSession Seeded(SessionState seed, bool requestsCloudRecovery) =>
        new(seed, Journal: null, LegacySelection: null, Favicons: [], requestsCloudRecovery);

    private static (JsonObject Document, SessionState Session, IReadOnlyList<TabFavicon> Favicons)? Decode(byte[] bytes) {
        try {
            if (bytes.Length is 0 or > NativeSessionAuthority.MaximumBytes
                || JsonNode.Parse(bytes, documentOptions: DocumentOptions) is not JsonObject document) return null;
            return (document, StoredSessionCodec.DecodeInstalledSession(document), StoredSessionCodec.DecodeInlineFavicons(document));
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            return null;
        }
    }

    #endregion
}
