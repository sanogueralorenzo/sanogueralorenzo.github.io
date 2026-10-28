using System.Buffers.Binary;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A Chromium session file, as Chrome, Arc and the other browsers built on
/// Chromium write it: `SNSS`, version 3,
/// then commands that each change a window or tab, replayed in order. A
/// version 5 file is encrypted with its profile's key and cannot be read
/// outside its browser.
internal sealed class ChromiumSession {
    #region Static Variables

    private static readonly byte[] Header = "SNSS"u8.ToArray();
    private const uint ReadableVersion = 3;
    private const uint EncryptedVersion = 5;

    /// The longest address and title a navigation keeps.
    private const int MaximumAddressBytes = 8_192;
    private const int MaximumTitleUnits = 4_096;
    /// The page state a navigation carries, which a reader skips.
    private const int MaximumPageStateBytes = 8 * 1024 * 1024;
    private const int MaximumWindowTitleBytes = 4_096;
    private const int MaximumGroupTitleUnits = 4_096;
    /// Where a tab's group or split token and whether it has one sit in the
    /// command that sets it, as Chromium lays its struct out.
    private const int TokenOffset = 8;
    private const int TokenFlagOffset = 24;

    #endregion

    #region Types

    private sealed class Tab(DateTimeOffset lastActivatedAt) {
        public int? Window { get; set; }
        public int VisualIndex { get; set; } = int.MaxValue;
        public int SelectedNavigation { get; set; }
        public Dictionary<int, Navigation> Navigations { get; set; } = [];
        public bool IsPinned { get; set; }
        public DateTimeOffset LastActivatedAt { get; set; } = lastActivatedAt;
        /// The tab group and split view the tab is in, by their tokens.
        public string? Group { get; set; }
        public string? Split { get; set; }
    }

    private sealed record Group(string Title, TabGroupColor Color);

    private sealed class Window {
        public int SelectedVisualIndex { get; set; }
        public string? Title { get; set; }
    }

    private sealed record Navigation(int Index, string Title, ImportAddress Address);

    #endregion

    #region Variables

    private readonly DateTimeOffset importedAt;
    private readonly Dictionary<int, Tab> tabs = [];
    private readonly Dictionary<int, Window> windows = [];
    private readonly HashSet<int> closedTabs = [];
    private readonly HashSet<int> closedWindows = [];
    private readonly Dictionary<string, Group> groups = new(StringComparer.Ordinal);
    private int? activeWindow;
    private bool hasInitialState;

    #endregion

    #region Constructors

    private ChromiumSession(DateTimeOffset importedAt) => this.importedAt = importedAt;

    #endregion

    #region Actions - Reading

    /// Whether `contents` starts as a Chromium session file does.
    public static bool Recognizes(ReadOnlySpan<byte> contents) => contents.StartsWith(Header);

    /// The windows the session left open, the active one first, each with
    /// its tabs in order. A tab not active since the session began is dated
    /// `importedAt`. Throws `Rejected` with `SessionEncrypted` or
    /// `SessionUnrecognized`.
    public static IReadOnlyList<SessionDraft> Read(ReadOnlySpan<byte> contents, DateTimeOffset importedAt,
        ChromiumSessionDialect? dialect = null) {
        dialect ??= ChromiumSessionDialect.Chromium;
        if (contents.Length < 8 || !Recognizes(contents)) throw new Rejected(new SessionUnrecognized());
        uint version = BinaryPrimitives.ReadUInt32LittleEndian(contents[4..]);
        if (version == EncryptedVersion) throw new Rejected(new SessionEncrypted());
        if (version != ReadableVersion) throw new Rejected(new SessionUnrecognized());
        var session = new ChromiumSession(importedAt);
        int position = 8;
        while (position < contents.Length) {
            if (contents.Length - position < 2) throw new Rejected(new SessionUnrecognized());
            int size = BinaryPrimitives.ReadUInt16LittleEndian(contents[position..]);
            if (size < 1 || size > contents.Length - position - 2) throw new Rejected(new SessionUnrecognized());
            var payload = contents.Slice(position + 3, size - 1);
            if (dialect.Command(contents[position + 2]) is { } command && ChromiumSessionCommand.Of(command) is { } known
                && !known.Apply(session, payload))
                throw new Rejected(new SessionUnrecognized());
            position += 2 + size;
        }
        if (!session.hasInitialState) throw new Rejected(new SessionUnrecognized());
        return session.Drafts();
    }

    private List<SessionDraft> Drafts() {
        var open = windows.Keys.Where(id => !closedWindows.Contains(id)).Order().ToArray();
        var ordinals = open.Select((id, index) => (id, index + 1)).ToDictionary(pair => pair.id, pair => pair.Item2);
        List<SessionDraft> drafts = [];
        foreach (int windowId in open) {
            var shown = tabs.Where(pair => pair.Value.Window == windowId && !closedTabs.Contains(pair.Key))
                .OrderBy(pair => pair.Value.VisualIndex).ThenBy(pair => pair.Key)
                .Select(pair => (Tab: pair.Value, Navigation: Selected(pair.Value)))
                .Where(pair => pair.Navigation is not null)
                .Select(pair => new SessionTab(pair.Navigation!.Title, pair.Navigation.Address,
                    pair.Tab.IsPinned ? TabPlacement.Pinned : TabPlacement.Current, pair.Tab.IsPinned ? null : pair.Tab.Group,
                    pair.Tab.LastActivatedAt, pair.Tab.Split))
                .ToArray();
            if (shown.Length == 0) continue;
            // Each tab group the window's open tabs are in becomes a folder among them, in the group's color.
            SessionFolder[] folders = [.. shown.Select(tab => tab.FolderSourceId).OfType<string>().Distinct(StringComparer.Ordinal)
                .Select(token => groups.TryGetValue(token, out var group)
                    ? new SessionFolder(token, group.Title, ParentSourceId: null, TabPlacement.Current, group.Color)
                    : new SessionFolder(token, "", ParentSourceId: null, TabPlacement.Current, TabGroupColor.Grey))];
            drafts.Add(new SessionDraft(ordinals[windowId], windows[windowId].Title, folders, shown));
        }
        if (activeWindow is { } active && ordinals.TryGetValue(active, out int ordinal)
            && drafts.FindIndex(draft => draft.Ordinal == ordinal) is > 0 and var index) {
            var first = drafts[index];
            drafts.RemoveAt(index);
            drafts.Insert(0, first);
        }
        return drafts;
    }

    /// The navigation a tab shows: its selected one, else the first after
    /// it, else its last.
    private static Navigation? Selected(Tab tab) {
        if (tab.Navigations.TryGetValue(tab.SelectedNavigation, out var selected)) return selected;
        var ordered = tab.Navigations.Values.OrderBy(navigation => navigation.Index).ToArray();
        return ordered.FirstOrDefault(navigation => navigation.Index >= tab.SelectedNavigation) ?? ordered.LastOrDefault();
    }

    #endregion

    #region Actions - Commands

    internal bool SetTabWindow(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } window || Int32(payload, 4) is not { } tab) return false;
        EditTab(tab, value => value.Window = window);
        if (!closedWindows.Contains(window)) windows.TryAdd(window, new Window());
        return true;
    }

    internal bool SetTabIndex(ReadOnlySpan<byte> payload) =>
        EditTab(payload, (tab, index) => tab.VisualIndex = index);

    internal bool PruneFromBack(ReadOnlySpan<byte> payload) =>
        EditTab(payload, (tab, count) => tab.Navigations = tab.Navigations.Where(pair => pair.Key < count).ToDictionary());

    internal bool UpdateNavigation(ReadOnlySpan<byte> payload) {
        var pickle = new ChromiumPickle(payload);
        if (!pickle.IsValid || pickle.Int32() is not { } tab || pickle.Int32() is not { } index
            || pickle.Utf8(MaximumAddressBytes) is not { } address || pickle.Utf16(MaximumTitleUnits) is not { } title
            || pickle.Utf8(MaximumPageStateBytes) is null || pickle.Int32() is null) return false;
        if (ImportAddress.Read(address) is not { } kept) return true;
        EditTab(tab, value => value.Navigations[index] = new Navigation(index, title, kept));
        return true;
    }

    internal bool SetSelectedNavigation(ReadOnlySpan<byte> payload) =>
        EditTab(payload, (tab, index) => tab.SelectedNavigation = index);

    internal bool SetSelectedTab(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } window || Int32(payload, 4) is not { } index) return false;
        EditWindow(window, value => value.SelectedVisualIndex = index);
        return true;
    }

    internal bool PruneFromFront(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } tab || Int32(payload, 4) is not { } count) return false;
        if (count > 0) Prune(tab, index: 0, count);
        return true;
    }

    internal bool SetPinned(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } tab || payload.Length < 5) return false;
        bool pinned = payload[4] != 0;
        EditTab(tab, value => value.IsPinned = pinned);
        return true;
    }

    internal bool CloseTab(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } tab) return false;
        tabs.Remove(tab);
        closedTabs.Add(tab);
        return true;
    }

    internal bool CloseWindow(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } window) return false;
        windows.Remove(window);
        closedWindows.Add(window);
        return true;
    }

    internal bool SetActiveWindow(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } window) return false;
        activeWindow = window;
        return true;
    }

    internal bool SetLastActiveTime(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } tab || payload.Length < 16) return false;
        long microseconds = BinaryPrimitives.ReadInt64LittleEndian(payload[8..]);
        var date = ImportDate.FromWindowsMicroseconds(microseconds);
        EditTab(tab, value => value.LastActivatedAt = date ?? importedAt);
        return true;
    }

    internal bool PruneRange(ReadOnlySpan<byte> payload) {
        if (Int32(payload, 0) is not { } tab || Int32(payload, 4) is not { } index || Int32(payload, 8) is not { } count) return false;
        if (index >= 0 && count > 0) Prune(tab, index, count);
        return true;
    }

    /// The tab group a tab joins or leaves. A payload Chromium does not lay
    /// out this way, as another browser built on it may write under the same
    /// command, changes nothing.
    internal bool SetTabGroup(ReadOnlySpan<byte> payload) => SetToken(payload, (tab, token) => tab.Group = token);

    /// The split view a tab joins or leaves, read as `SetTabGroup` is.
    internal bool SetSplitTab(ReadOnlySpan<byte> payload) => SetToken(payload, (tab, token) => tab.Split = token);

    /// A tab group's title and color. One that does not read as Chromium
    /// writes it changes nothing.
    internal bool SetTabGroupMetadata(ReadOnlySpan<byte> payload) {
        var pickle = new ChromiumPickle(payload);
        if (pickle.IsValid && pickle.UInt64() is { } high && pickle.UInt64() is { } low && pickle.Utf16(MaximumGroupTitleUnits) is { } title
            && pickle.Int32() is { } color)
            groups[Token(high, low)] = new Group(title, color >= 0 && color < TabGroupColor.All.Count ? TabGroupColor.All[color] : TabGroupColor.Grey);
        return true;
    }

    private bool SetToken(ReadOnlySpan<byte> payload, Action<Tab, string?> set) {
        if (Int32(payload, 0) is not { } tab || payload.Length <= TokenFlagOffset) return true;
        string? token = payload[TokenFlagOffset] == 0 ? null
            : Token(BinaryPrimitives.ReadUInt64LittleEndian(payload[TokenOffset..]), BinaryPrimitives.ReadUInt64LittleEndian(payload[(TokenOffset + 8)..]));
        EditTab(tab, value => set(value, token));
        return true;
    }

    private static string Token(ulong high, ulong low) => $"{high:x16}{low:x16}";

    internal bool SetWindowTitle(ReadOnlySpan<byte> payload) {
        var pickle = new ChromiumPickle(payload);
        if (!pickle.IsValid || pickle.Int32() is not { } window || pickle.Utf8(MaximumWindowTitleBytes) is not { } title) return false;
        EditWindow(window, value => value.Title = title);
        return true;
    }

    /// Chromium's marker that the commands before it restore the session is
    /// empty. Opera writes its own records under the same command, which
    /// carry data and mark nothing.
    internal bool MarkInitialState(ReadOnlySpan<byte> payload) {
        if (payload.IsEmpty) hasInitialState = true;
        return true;
    }

    #endregion

    #region Actions - Editing

    /// Applies `edit` with the tab and the integer after it in `payload`.
    private bool EditTab(ReadOnlySpan<byte> payload, Action<Tab, int> edit) {
        if (Int32(payload, 0) is not { } tab || Int32(payload, 4) is not { } value) return false;
        EditTab(tab, found => edit(found, value));
        return true;
    }

    private void EditTab(int id, Action<Tab> edit) {
        if (closedTabs.Contains(id)) return;
        if (!tabs.TryGetValue(id, out var tab)) tabs[id] = tab = new Tab(importedAt);
        edit(tab);
    }

    private void EditWindow(int id, Action<Window> edit) {
        if (closedWindows.Contains(id)) return;
        if (!windows.TryGetValue(id, out var window)) windows[id] = window = new Window();
        edit(window);
    }

    /// Removes `count` navigations from `index` and moves those after them
    /// down, keeping the selection on the page it showed where it can.
    private void Prune(int id, int index, int count) => EditTab(id, tab => {
        long upper = (long)index + count;
        Dictionary<int, Navigation> kept = [];
        foreach (var navigation in tab.Navigations.Values) {
            if (navigation.Index < index) kept[navigation.Index] = navigation;
            else if (navigation.Index >= upper) kept[navigation.Index - count] = navigation with { Index = navigation.Index - count };
        }
        tab.Navigations = kept;
        if (tab.SelectedNavigation >= upper) tab.SelectedNavigation -= count;
        else if (tab.SelectedNavigation >= index) tab.SelectedNavigation = Math.Max(0, index - 1);
    });

    private static int? Int32(ReadOnlySpan<byte> payload, int offset) =>
        offset >= 0 && payload.Length - offset >= 4 ? BinaryPrimitives.ReadInt32LittleEndian(payload[offset..]) : null;

    #endregion
}
