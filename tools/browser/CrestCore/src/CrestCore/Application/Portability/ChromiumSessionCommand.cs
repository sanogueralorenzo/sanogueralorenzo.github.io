namespace CrestCore.Application;

/// A command a Chromium session file replays, by the identifier Chromium
/// writes, and what it changes. A command this reader does not know changes
/// nothing.
internal sealed class ChromiumSessionCommand {
    #region Static Variables

    public static readonly ChromiumSessionCommand SetTabWindow = new(0, (session, payload) => session.SetTabWindow(payload));
    public static readonly ChromiumSessionCommand SetTabIndexInWindow = new(2, (session, payload) => session.SetTabIndex(payload));
    public static readonly ChromiumSessionCommand TabNavigationPathPrunedFromBack = new(5,
        (session, payload) => session.PruneFromBack(payload));
    public static readonly ChromiumSessionCommand UpdateTabNavigation = new(6, (session, payload) => session.UpdateNavigation(payload));
    public static readonly ChromiumSessionCommand SetSelectedNavigationIndex = new(7,
        (session, payload) => session.SetSelectedNavigation(payload));
    public static readonly ChromiumSessionCommand SetSelectedTabInIndex = new(8, (session, payload) => session.SetSelectedTab(payload));
    public static readonly ChromiumSessionCommand TabNavigationPathPrunedFromFront = new(11,
        (session, payload) => session.PruneFromFront(payload));
    public static readonly ChromiumSessionCommand SetPinnedState = new(12, (session, payload) => session.SetPinned(payload));
    public static readonly ChromiumSessionCommand TabClosed = new(16, (session, payload) => session.CloseTab(payload));
    public static readonly ChromiumSessionCommand WindowClosed = new(17, (session, payload) => session.CloseWindow(payload));
    public static readonly ChromiumSessionCommand SetActiveWindow = new(20, (session, payload) => session.SetActiveWindow(payload));
    public static readonly ChromiumSessionCommand LastActiveTime = new(21, (session, payload) => session.SetLastActiveTime(payload));
    public static readonly ChromiumSessionCommand TabNavigationPathPruned = new(24, (session, payload) => session.PruneRange(payload));
    public static readonly ChromiumSessionCommand SetTabGroup = new(25, (session, payload) => session.SetTabGroup(payload));
    public static readonly ChromiumSessionCommand SetTabGroupMetadata = new(27, (session, payload) => session.SetTabGroupMetadata(payload));
    public static readonly ChromiumSessionCommand SetWindowTitle = new(31, (session, payload) => session.SetWindowTitle(payload));
    public static readonly ChromiumSessionCommand SetSplitTab = new(36, (session, payload) => session.SetSplitTab(payload));
    public static readonly ChromiumSessionCommand InitialStateMarker = new(255,
        (session, payload) => session.MarkInitialState(payload));
    /// Opera keeps the marker at 252, since it writes records of its own at 255.
    public static readonly ChromiumSessionCommand OperaInitialStateMarker = new(252,
        (session, payload) => session.MarkInitialState(payload));

    public static IReadOnlyList<ChromiumSessionCommand> All { get; } = [SetTabWindow, SetTabIndexInWindow,
        TabNavigationPathPrunedFromBack, UpdateTabNavigation, SetSelectedNavigationIndex, SetSelectedTabInIndex,
        TabNavigationPathPrunedFromFront, SetPinnedState, TabClosed, WindowClosed, SetActiveWindow, LastActiveTime,
        TabNavigationPathPruned, SetTabGroup, SetTabGroupMetadata, SetWindowTitle, SetSplitTab, InitialStateMarker,
        OperaInitialStateMarker];

    #endregion

    #region Types

    /// Applies a command's payload to a session, answering false for a
    /// payload the command cannot hold.
    private delegate bool Applier(ChromiumSession session, ReadOnlySpan<byte> payload);

    #endregion

    #region Variables

    /// The identifier Chromium writes for the command.
    public byte Id { get; }

    private readonly Applier apply;

    #endregion

    #region Constructors

    private ChromiumSessionCommand(byte id, Applier apply) {
        Id = id;
        this.apply = apply;
    }

    #endregion

    #region Actions - Replaying

    public static ChromiumSessionCommand? Of(byte id) => All.FirstOrDefault(command => command.Id == id);

    /// Applies the command to `session`; false for a payload it cannot hold.
    public bool Apply(ChromiumSession session, ReadOnlySpan<byte> payload) => apply(session, payload);

    #endregion
}
