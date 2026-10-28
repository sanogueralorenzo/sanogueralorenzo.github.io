using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    internal SearchProvider SearchProvider => device?.SearchProvider ?? Current.AppPreferences?.SearchProvider ?? AppPreferences.Default.SearchProvider;

    #endregion

    #region Actions - Addresses

    /// What `input` loads with `provider`: no address when it names nothing a
    /// page can load.
    internal static ResolvedAddress Resolved(string input, SearchProvider provider, bool allowsInternalPages) {
        AddressResolution? resolution;
        try {
            resolution = AddressResolution.Resolve(input, provider, allowsInternalPages);
        } catch (Rejected refused) when (refused.Rejection is UnsupportedAddress) {
            return new(Url: null, SearchQuery: null);
        }
        return resolution is not null && Uri.TryCreate(resolution.Url, UriKind.Absolute, out _)
            ? new(resolution.Url, resolution.SearchQuery) : new(Url: null, SearchQuery: null);
    }

    /// What a Space of the accepted session searches with. Throws `Rejected`
    /// with `UnknownSpace` for one it does not hold.
    internal SearchProvider Searches(Guid spaceId) {
        lock (Gate) {
            if (!session.Spaces.Any(space => space.Id == spaceId)) throw new Rejected(new UnknownSpace(spaceId));
        }
        return SearchProvider;
    }

    #endregion

    #region Actions - Browsing preferences

    /// Whether two states of one Space hold the same tabs, history and archive.
    internal bool SameRecords(SpaceState before, SpaceState after) =>
        before.Tabs.SequenceEqual(after.Tabs) && before.History.SequenceEqual(after.History)
        && before.ArchivedTabs.SequenceEqual(after.ArchivedTabs);

    #endregion
}
