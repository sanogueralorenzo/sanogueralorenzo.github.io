using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A tab while its Space's organization is being edited. Its durable value is
/// <see cref="State"/>; every rule below replaces that value rather than keeping a
/// second copy of any field.
public sealed class BrowserTab {
    #region Variables

    /// The most characters a rename keeps.
    public const int MaximumTitleLength = 4096;

    public TabState State { get; private set; }

    public Guid Id => State.Id;
    public TabKind Content => TabKind.FromStored(State.NativeContent?.Kind, State.Url, State.Title);
    public string? Url => State.Url;
    public string Title => State.Title;
    public string? CustomTitle => State.CustomTitle;
    public string? SavedUrl => State.SavedUrl;
    public TabPlacement Placement => State.Placement;
    public Guid? FolderId => State.FolderId;
    public Guid? SplitGroupId => State.SplitGroupId;
    public DateTimeOffset LastActivatedAt => State.LastActivatedAt;

    public TabIconMode IconMode => State.IconMode;
    public bool KeepsPageLoaded => State.KeepsPageLoaded;

    #endregion

    #region Constructors

    private BrowserTab(TabState state) => State = state;

    #endregion

    #region Actions - Persistence

    /// A stored tab, with a blank rename read as no rename. A web page needs an
    /// address and nothing else may have one, and a native view names its
    /// kind. Refused with `InvalidTabContent` otherwise.
    public static BrowserTab Restore(TabState state) {
        var restored = state with { CustomTitle = string.IsNullOrWhiteSpace(state.CustomTitle) ? null : state.CustomTitle.Trim() };
        if (restored.NativeContent is { } native && (string.IsNullOrWhiteSpace(native.Kind) || restored.Url is not null))
            throw new Rejected(new InvalidTabContent(restored.Id));
        return new(restored);
    }

    #endregion

    #region Actions - Activity

    public void Activate(DateTimeOffset now) => State = State with { LastActivatedAt = now };

    #endregion

    #region Actions - Pages

    /// A page reporting where it landed and what it is called. A URL entered
    /// while a native view is shown replaces that view with a web page, since
    /// persisting both is an impossible tab. A blank title is the page saying
    /// nothing rather than clearing the name.
    public void ObserveAppearance(string? url, string? title) {
        if (url is not null) State = State with { NativeContent = null, Url = url };
        if (!string.IsNullOrEmpty(title)) State = State with { Title = title };
    }

    /// A closed saved tab reopens at the address it was saved with.
    public void ReturnToSavedUrl() {
        if (SavedUrl is { } saved) State = State with { Url = saved };
    }

    #endregion

    #region Actions - Saved address

    /// Adopts the page the tab shows as the one it belongs to. A tab at its
    /// saved address keeps it. Refused with `NoSavedAddress` for a tab that
    /// belongs nowhere.
    public void ReplaceSavedAddress() {
        _ = RequiredSavedAddress();
        if (State.IsAwayFromSavedAddress) State = State with { SavedUrl = Url };
    }

    /// Returns the tab to the address it belongs to, which its page then
    /// loads. Refused with `NoSavedAddress` for a tab that belongs nowhere.
    public void ReturnToSavedAddress() => State = State with { Url = RequiredSavedAddress() };

    private string RequiredSavedAddress() => State.SavedAddress ?? throw new Rejected(new NoSavedAddress(Id));

    #endregion

    #region Actions - Icon

    /// The icon slot's symbol, the address its cached favicon came from, the
    /// color behind it and the mode that chose them. Image bytes stay native.
    public void SetIcon(string symbol) => State = State with { Symbol = symbol };

    public void SetFavicon(string? url, TabIconAccent? accent) => State = State with { FaviconUrl = url, IconAccent = accent };

    /// The person chose how the icon is filled: a pulled favicon keeps the
    /// page's address and `accent` behind it, and any other choice keeps none.
    /// Answers whether the tab wears the image its chooser holds. Refused with
    /// `InvalidTabIcon` when the mode can make no icon from `emoji`.
    public bool ChooseIcon(TabIconMode mode, string? emoji, TabIconAccent? accent) {
        ArgumentNullException.ThrowIfNull(mode);
        SetIcon(mode.Symbol(emoji) ?? throw new Rejected(new InvalidTabIcon(mode)));
        SetFavicon(mode.RequiresFavicon ? Url : null, mode.RequiresFavicon ? accent : null);
        State = State with { StoredIconMode = mode };
        return mode.RequiresFavicon;
    }

    /// The page reported an icon for the document at `url`, which the tab
    /// shows. An icon that follows its page wears it, with the color the
    /// page's theme puts behind it; a chosen or pulled icon keeps what it has.
    /// Answers whether the tab wears it.
    public bool WearPageIcon(string url, TabIconAccent? accent) {
        if (!IconMode.FollowsPage) return false;
        SetIcon(TabIconMode.WebSymbol);
        SetFavicon(url, accent);
        return true;
    }

    #endregion

    #region Mutators

    /// Names the tab, trimmed; a blank name hands it back to its page's title.
    /// The name it already has changes nothing. Refused with `InvalidName`
    /// past `MaximumTitleLength`.
    public void Rename(string? title, DateTimeOffset now) {
        var custom = string.IsNullOrWhiteSpace(title) ? null : title.Trim();
        if (custom == CustomTitle) return;
        if (custom?.Length > MaximumTitleLength) throw new Rejected(new InvalidName(MaximumTitleLength));
        State = State with { CustomTitle = custom, TitleModifiedAt = BrowserEditTimestamp.Normalize(now) };
    }

    public void SetResidency(bool keepLoaded) => State = State with { KeepsPageLoaded = keepLoaded };

    internal void SetSplit(Guid? id) => State = State with { SplitGroupId = id };

    internal void MarkPosition(DateTimeOffset now) => State = State with { PositionModifiedAt = BrowserEditTimestamp.Normalize(now) };

    public void Place(TabPlacement placement, Guid? folder, DateTimeOffset? now = null, bool preservesSplit = false) {
        if (Placement == placement && FolderId == folder) return;
        var savedUrl = placement.IsDurable ? SavedUrl ?? Url : null;
        State = State with {
            SavedUrl = savedUrl,
            Placement = placement,
            FolderId = folder,
            SplitGroupId = preservesSplit ? SplitGroupId : null
        };
        if (now is { } changedAt) MarkPosition(changedAt);
    }

    #endregion
}
