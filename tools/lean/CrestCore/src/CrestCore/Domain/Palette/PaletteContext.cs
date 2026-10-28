using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Everything one answer of a window's palette reads, captured once: the
/// Space the window shows and the tab it shows there, whether the window is
/// private and its engine opens internal pages, the workspace's other Spaces,
/// its history and the time. Each kind of result reads it to find its rows,
/// and each signal to score them. It reads only immutable records, so a
/// palette answers without holding the core's lock.
internal sealed class PaletteContext {
    #region Variables

    public SpaceState? Space { get; }

    /// The tab the window shows, which the palette leaves out.
    public Guid? ShownTabId { get; }

    public bool IsPrivate { get; }
    public bool AllowsInternalPages { get; }
    /// The workspace's other Spaces the palette may offer.
    public IReadOnlyList<SpaceState> Spaces { get; }

    public DateTimeOffset Now { get; }
    public SearchProvider Provider { get; }
    public bool Suggests { get; }

    /// The Space's history by address, or null without a Space.
    public AddressIndex? History { get; }

    #endregion

    #region Constructors

    public PaletteContext(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages,
        IReadOnlyList<SpaceState> spaces, DateTimeOffset now, SearchProvider provider, bool suggests) {
        Space = space;
        ShownTabId = shownTabId;
        IsPrivate = isPrivate;
        AllowsInternalPages = allowsInternalPages;
        Spaces = spaces;
        Now = now;
        Provider = provider;
        Suggests = suggests;
        History = space is null ? null : AddressIndex.Of(space.History);
    }

    #endregion

    #region Actions - Evidence

    /// What ranking reads of a place whose row `row` shows `title` at `url`,
    /// for `query`: how well the text matches it and whether it starts the
    /// title or the address, how much the page was used, when its tab was,
    /// whether it is open or kept, using history visits. Null when the
    /// text matches neither; with nothing typed, as when the person narrowed
    /// the palette to a kind, every place matches with no text points.
    public PaletteEvidence? Evidence(PaletteQuery query, PaletteRow row, string title, string? url, DateTimeOffset? lastUsed = null,
        bool isOpen = false, bool isKept = false, HistoryEntryState? entry = null) {
        string address = url is null ? "" : new WebAddress(url).Place ?? "";
        bool prefixesTitle = query.Prefixes(title);
        bool prefixes = prefixesTitle || address.Length > 0 && query.Prefixes(address);
        int? score = query.IsEmpty ? 0 : query.Score(title, address);
        if (prefixes) score = Math.Max(score ?? 0, TextMatch.TextStart.Points);
        if (score is not { } matched) return null;
        entry ??= url is not null && new WebAddress(url).Normalized is { } normalized ? History?.Entry(normalized) : null;
        double frecency = entry is null ? 0 : Math.Max(1, entry.VisitCount) * Math.Pow(2, -(Now - entry.LastVisitedAt).TotalDays / 30);
        return new(matched, prefixes, prefixesTitle, frecency, lastUsed, isOpen, isKept);
    }

    /// What ranking reads of a row that matched with `score` and is no
    /// place: only the text match.
    public PaletteEvidence Matched(PaletteQuery query, PaletteRow row, int score) =>
        new(score, Prefixes: false, PrefixesTitle: query.Prefixes(row.Title), Frecency: 0, LastUsed: null, IsOpen: false, IsKept: false);

    #endregion

    #region Actions - Support

    /// The host `url` names, or null for none.
    public static string? Host(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : null;

    #endregion
}

/// What ranking reads of one row: how well the text matched it, whether the
/// text starts its title or address, how much its page was used, when its tab
/// was last used, and whether it is open or kept.
internal sealed record PaletteEvidence(int Match, bool Prefixes, bool PrefixesTitle, double Frecency, DateTimeOffset? LastUsed, bool IsOpen,
    bool IsKept);
