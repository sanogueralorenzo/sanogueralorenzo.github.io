namespace CrestCore.Contracts;

#region Intents

/// What a new tab shows: the page at `Address`, the native view `View`, or,
/// with neither, the Start Page. `Title` names a page until it loads and
/// reports its own; a page without one is titled by its host. A native view
/// titles and draws its tab itself.
public sealed record TabContent(string? Address, NativeView? View, string? Title);

#endregion

#region Rejections

/// The tab is in a split, and the section it would move to holds no splits,
/// so it moves only by leaving its split.
public sealed record CannotPinSplit(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Split View groups cannot be pinned. Separate the split first.";

    #endregion
}

/// The tab shows the Start Page and is its Space's only tab, so closing it
/// leaves nothing but its window to close.
public sealed record LastStartPage(Guid TabId) : Rejection;

/// The Space has no open tab to clear.
public sealed record NoCurrentTabs(Guid SpaceId) : Rejection;

/// The Space already pins `Capacity` tabs, so it pins no more.
public sealed record PinnedTabsFull(int Capacity) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Capacity))]
    public string Message => "A Space can hold up to %lld pinned tabs. Unpin tabs or select fewer tabs.";

    #endregion
}

/// The tab shows the Start Page, which has nothing to copy.
public sealed record StartPageNotCopied(Guid TabId) : Rejection;

#endregion
