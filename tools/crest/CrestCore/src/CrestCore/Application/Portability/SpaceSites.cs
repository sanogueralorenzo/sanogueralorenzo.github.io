using System.Net;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The hosts a Space's tabs show or were saved at, and every domain those
/// hosts are, or are a subdomain of, compared ignoring case: what a browser's
/// saved password belongs with when the browser names its own Spaces.
internal sealed record SpaceSites(IReadOnlySet<string> Hosts, IReadOnlySet<string> Domains) {
    #region Actions - Sites

    /// Each Space's sites, by Space.
    internal static IReadOnlyDictionary<Guid, SpaceSites> Of(IReadOnlyList<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(spaces);
        var sites = new Dictionary<Guid, SpaceSites>();
        foreach (var space in spaces) {
            var hosts = space.Tabs.Select(tab => ImportAddress.Read(tab.SavedUrl ?? tab.Url)?.Host).OfType<string>()
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            sites[space.Id] = new(hosts, hosts.SelectMany(DomainsOf).ToHashSet(StringComparer.OrdinalIgnoreCase));
        }
        return sites;
    }

    /// Whether the sites hold `host`, a subdomain of it, or a domain it is a
    /// subdomain of, each at a dot.
    internal bool Holds(string host) => Domains.Contains(host) || DomainsOf(host).Any(Hosts.Contains);

    /// `host` and each domain it is a subdomain of, at a dot: itself only for
    /// an address.
    private static IEnumerable<string> DomainsOf(string host) {
        yield return host;
        if (IPAddress.TryParse(host, out _)) yield break;
        for (int dot = host.IndexOf('.', StringComparison.Ordinal); dot >= 0 && dot + 1 < host.Length;
            dot = host.IndexOf('.', dot + 1)) yield return host[(dot + 1)..];
    }

    #endregion
}
