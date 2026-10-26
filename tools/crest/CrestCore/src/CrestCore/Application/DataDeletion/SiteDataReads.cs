using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Lists the sites that keep data in a profile. Every registered engine is
/// asked, started or not, since a profile's store outlives the run that filled
/// it, and a reading ends with `WebsiteDataRead` once each has answered: the
/// sites every engine listed, merged by name. Nothing here is saved.
internal sealed class SiteDataReads(Engines engines, IIdSource ids) {
    #region Types

    /// One reading, until every engine asked has answered.
    internal sealed class Reading(Guid requestId, Guid profileId, string? host) {
        public Guid RequestId { get; } = requestId;
        /// The profile whose sites the reading lists.
        public Guid ProfileId { get; } = profileId;
        /// The host whose own sites the reading keeps, or nil for every site.
        public string? Host { get; } = host;
        /// The readings still out, each with the engine it went to.
        public Dictionary<Guid, Engine> Waiting { get; } = [];
        /// The sites listed so far, by name.
        public SortedDictionary<string, StoredSite> Sites { get; } = new(StringComparer.Ordinal);
        public bool Complete { get; set; } = true;
    }

    #endregion

    #region Variables

    /// Each reading an engine has yet to answer, with its reading.
    internal Dictionary<Guid, Reading> ByReading { get; } = [];

    #endregion

    #region Actions - Readings

    /// Asks every registered engine which sites keep data in profile
    /// `profileId`, keeping only `host`'s own when it is given.
    internal void Start(Guid requestId, Guid profileId, bool ephemeral, string? host, Device device, ChangeFeed changes,
        Action<Engine, EngineCommand> issue) {
        var reading = new Reading(requestId, profileId, host);
        foreach (var engine in engines.All) {
            var id = ids.Next();
            reading.Waiting[id] = engine;
            ByReading[id] = reading;
            issue(engine, new ReadSiteData(profileId, ephemeral, id));
        }
        if (reading.Waiting.Count == 0) Finish(reading, device, changes);
    }

    /// Adds one engine's sites to `reading`, merging a site another engine
    /// listed too.
    internal static void Add(Reading reading, IEnumerable<StoredSite> sites) {
        foreach (var listed in sites) {
            var name = SiteName(listed.Site);
            var site = reading.Sites.GetValueOrDefault(name) ?? new StoredSite(name, []);
            if (name.Length == 0 || reading.Host is { } host && !site.Covers(host)) continue;
            reading.Sites[name] = site.Keeping(listed.Kinds);
        }
    }

    /// `site` as the list names it: lowercase, without the dots around it or
    /// the brackets one engine puts around an IPv6 address and another leaves out.
    internal static string SiteName(string site) {
        var name = site.Trim().Trim('.').ToLowerInvariant();
        return name is ['[', .., ']'] ? name[1..^1] : name;
    }

    #endregion

    #region Actions - Reports

    /// Publishes what `reading` listed, or no site at all when a Space locked
    /// its profile while the engines answered, as the lock refuses a new
    /// reading.
    internal static void Finish(Reading reading, Device device, ChangeFeed changes) {
        var locked = device.LockedSpace(reading.ProfileId) is not null;
        changes.Publish(new WebsiteDataRead(reading.RequestId, locked ? [] : [.. reading.Sites.Values], reading.Complete && !locked));
    }

    #endregion
}
