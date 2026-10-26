using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One page this device hosts: its owner, the window that hosts it, the engine
/// that hosts it, where it stands there and its live state. Its engine page
/// lives in the profile of the Space it opened in, so the page only ever moves
/// between Spaces of that profile. It may move to another engine, which
/// creates it anew in that profile.
internal sealed class Page {
    #region Static Variables

    /// How long after its document is recorded the page's visit still takes
    /// the titles the page gives itself, and how many. A page that names
    /// itself as it settles names its visit; one that later flashes news in
    /// its title, such as unread mail, leaves history alone. Its tab follows
    /// every title.
    public static readonly TimeSpan HistoryTitleWindow = TimeSpan.FromSeconds(5);
    public const int HistoryTitleChanges = 5;

    #endregion

    #region Variables

    public Guid Id { get; }
    public Engine Engine { get; private set; }
    public Guid ProfileId { get; }

    public Guid WorkspaceId { get; private set; }
    public Guid SpaceId { get; private set; }

    /// The tab that owns the page, or null for a transient request's page: a
    /// Quick Window's, a Peek's, or one of its engine's own pages in Settings.
    public Guid? TabId { get; private set; }

    /// The window that hosts the page. A window that shares its pages with
    /// others shows this page without owning it.
    public Guid WindowId { get; private set; }

    /// How the page presents while it has no tab, as it opened.
    public TransientPresentation? Transient { get; }

    /// Whether another page opened this one: a script's window, a link to a
    /// new tab or window, a link the person followed into a new tab, Peek or
    /// split, or an extension's tab or window, whose opener is the extension.
    /// Such a page runs on its opener's engine, the site's engine choice moves
    /// it only when the person asks for an address in it, and it may close
    /// itself.
    public bool OpenedByPage { get; }

    public PagePhase Phase { get; private set; } = PagePhase.Opening;

    public PageState State => new(Id, WorkspaceId, SpaceId, TabId, Engine.Kind, Phase, Live);

    /// What rules and views read of the page now: what its engine last showed,
    /// whether its history reaches back or forward, and why its latest
    /// navigation failed. A failure over the document the page still shows can
    /// be left for that document, so the page can go back even when its
    /// history cannot.
    public PageLiveState Live => new(shown.Url, shown.PendingUrl, shown.Title, shown.IsLoading,
        History.CanGoBack || failure is { ReplacedDocument: false } && shown.Url is not null, History.CanGoForward,
        shown.Security, failure, shown.Media);

    /// The page's back and forward history across the engines it moved
    /// through, as their reports and the page's moves left it.
    public PageHistory History { get; private set; } = new();

    /// The icon the engine last reported for the document the page shows.
    public PageIcon? Icon { get; private set; }

    /// What the page's engine last reported it shows, with the address the
    /// core asked it to load since.
    private PageSnapshot shown = PageSnapshot.Blank;

    /// Why the page's latest navigation failed, until another commits a new
    /// document or the page is asked to load or leave the failure.
    private PageFailure? failure;

    /// The address of the page the document shows, as it last committed or
    /// was recorded.
    private string? documentUrl;

    /// The address of the page the document shows, or null before one
    /// committed.
    public string? DocumentAddress => documentUrl;

    /// Whether the page has loaded nothing yet: its engine is still creating
    /// it, or created it and it neither shows a document nor heads to one.
    public bool AwaitsFirstLoad => Phase == PagePhase.Opening
        || Phase == PagePhase.Live && documentUrl is null && shown.Url is null && shown.PendingUrl is null;

    /// The document's navigation is recorded, or ended with nothing to record.
    private bool isRecorded;

    /// The document's record, while its title follows the page's: the title
    /// it last gave the tab and history, empty when the page had none, when
    /// it was recorded, and how often its visit took a later title.
    private (string Title, DateTimeOffset At, int VisitTitles)? record;

    /// How many documents the page has shown, so a question it answered can
    /// tell whether that document is still the one it shows.
    public long Documents { get; private set; }

    /// When the page left the screen, or null while a window shows it. Memory
    /// pressure unloads the pages off screen longest first.
    public DateTimeOffset? HiddenSince { get; private set; }

    /// Whether the page's engine last said a video of the page floats in
    /// Picture in Picture, or is about to.
    public bool ShowsPictureInPicture => Phase == PagePhase.Live && shown.Media.HasFlag(PageMediaActivity.PictureInPicture);

    /// Whether the page runs media its engine last reported: playing or
    /// audible, capturing a camera, microphone or screen, or holding a
    /// Picture in Picture window, playing or paused. Such a page stays loaded
    /// whatever memory pressure or cleanup would otherwise take.
    public bool RunsMedia => Phase == PagePhase.Live && shown.Media != PageMediaActivity.None;

    /// How many times in a row the page's renderer stopped where a window
    /// showed it, or came back once shown, since a document last finished
    /// loading or the person asked for one.
    private int crashes;

    /// Why the page's renderer stopped while nobody could see it, until a
    /// window shows the page and the core brings it back.
    private (string Domain, long Code)? stoppedUnseen;

    /// The page's renderer stopped while nobody could see it, and the core
    /// brings it back once a window shows it.
    public bool RecoversWhenShown => stoppedUnseen is not null;

    /// The address a page that moved to another engine loads once that
    /// engine has created it, and the history entry the load stands for when
    /// the page returned to one.
    private string? rehostedAddress;
    private Guid? rehostedEntry;

    /// Why the page moved to another engine, each reason once.
    private readonly HashSet<RehostReason> movedFor = [];

    /// The document already offered a protected-media fallback, if any.
    private long? protectedMediaAttempt;



    #endregion

    #region Constructors

    public Page(Guid id, Engine engine, Guid profileId, Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId,
        TransientPresentation? transient, bool openedByPage = false) {
        Id = id;
        Engine = engine;
        ProfileId = profileId;
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
        Transient = transient;
        OpenedByPage = openedByPage;
    }

    #endregion

    #region Actions - Lifecycle

    /// Moves the page to `next` when it may follow the phase the page is in,
    /// and answers whether it did.
    public bool Enter(PagePhase next) {
        if (!next.Follows(Phase)) return false;
        Phase = next;
        return true;
    }

    /// Gives the page a new owner in a Space of its profile, hosted by `windowId`.
    public void Move(Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId) {
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
    }

    /// The page moves to `engine` for `reason`, and `engine` opens it anew and
    /// loads `address` once it has created it. Nothing the old engine showed
    /// stays but the page's history, and the page shows itself heading to
    /// `address` at once.
    public void Rehost(Engine engine, string? address, RehostReason reason) {
        movedFor.Add(reason);
        History.Leave(engine.Kind, address);
        Arrive(engine, address, load: address, entry: null);
    }

    /// The page goes back or forward to a history entry another engine held,
    /// and `engine` opens it anew, heading to `address`: restoring the
    /// history it kept, or loading `entry` afresh once it created the page.
    /// A return is no move of the page's own, so it records no reason.
    public void Return(Engine engine, string address, Guid? entry) =>
        Arrive(engine, address, load: entry is null ? null : address, entry);

    /// The page opens anew on `engine`, heading to `address`, and loads
    /// `load` once created, as `entry` when it names one.
    private void Arrive(Engine engine, string? address, string? load, Guid? entry) {
        Engine = engine;
        Phase = PagePhase.Opening;
        rehostedAddress = load;
        rehostedEntry = entry;
        shown = PageSnapshot.Blank with { PendingUrl = address };
        failure = null;
        documentUrl = null;
        isRecorded = false;
        record = null;
        Icon = null;
        crashes = 0;
        stoppedUnseen = null;
    }

    /// Attempts fallback once per document, so repeated capability probes
    /// never repeat a canceled before-unload prompt.
    public bool TryProtectedMediaFallback() {
        if (protectedMediaAttempt == Documents) return false;
        protectedMediaAttempt = Documents;
        return true;
    }

    /// Whether the page ever moved to another engine for `reason`.
    public bool MovedFor(RehostReason reason) => movedFor.Contains(reason);

    /// The load the page makes now that its new engine created it, taken
    /// once: its address and the history entry it stands for, if any; null
    /// for a page that did not move, or one whose engine restores history.
    public LoadPage? TakeRehostedLoad() {
        if (rehostedAddress is not { } address) return null;
        var load = new LoadPage(Id, address, rehostedEntry);
        rehostedAddress = null;
        rehostedEntry = null;
        return load;
    }

    #endregion

    #region Actions - Navigation

    /// A navigation took effect at `url`. A new document begins a record of
    /// its own, without the icon of the one it replaced. A move within the
    /// document begins one only when it reaches another page: a fragment is
    /// part of the page it names, and the document keeps its icon.
    public void Commit(string url, bool sameDocument) {
        if (!sameDocument) {
            failure = null;
            stoppedUnseen = null;
            Documents++;
        }
        if (sameDocument && documentUrl is { } shown && new WebAddress(shown).IsSamePage(new WebAddress(url))) return;
        documentUrl = url;
        isRecorded = false;
        record = null;
        if (!sameDocument) Icon = null;
    }

    /// A navigation finished at `url`, titled `title`, at `now`. Answers
    /// whether it is the first finish of its document, which the core
    /// records; a later one records nothing.
    public bool Finish(string url, string title, DateTimeOffset now) {
        crashes = 0;
        if (isRecorded) return false;
        documentUrl = url;
        isRecorded = true;
        record = (title, now, 0);
        return true;
    }

    /// The title the page gave its recorded document since, which its tab
    /// and, while `HistoryTitleWindow` and `HistoryTitleChanges` allow, its
    /// visit take at `now`: the address of the record, the title, and whether
    /// the visit takes it. A visit recorded without a title takes the first
    /// one the page gives whenever it comes, as a page loaded out of sight
    /// names itself only once it is shown. Null while the page shows no title,
    /// the one recorded, or another page than the one recorded.
    public (string Url, string Title, bool Visit)? Retitle(DateTimeOffset now) {
        if (record is not var (recorded, at, visitTitles) || documentUrl is not { } url || string.IsNullOrEmpty(shown.Title)
            || shown.Title == recorded || shown.Url is not { } address || !new WebAddress(address).IsSamePage(new WebAddress(url)))
            return null;
        var visit = recorded.Length == 0 || now - at <= HistoryTitleWindow && visitTitles < HistoryTitleChanges;
        record = (shown.Title, at, visit ? visitTitles + 1 : visitTitles);
        return (url, shown.Title, visit);
    }

    /// A navigation failed as `reason` describes, so the document it was
    /// loading records nothing, and the page shows the failure in place of
    /// where it was heading.
    public void Fail(PageFailure reason) {
        isRecorded = true;
        record = null;
        failure = reason;
        shown = shown with { PendingUrl = null };
    }

    /// The page is asked to load `url`, and shows it heading there at once.
    /// A load the person asks for starts crash recovery over.
    public void Load(string url) {
        failure = null;
        crashes = 0;
        stoppedUnseen = null;
        shown = shown with { PendingUrl = url };
    }

    /// The load the page was heading to will not happen, so it shows the
    /// document it had.
    public void CancelLoad() => shown = shown with { PendingUrl = null, IsLoading = false };

    /// The person left the page's failure for the document behind it.
    public void LeaveFailure() => failure = null;

    /// The page restores what an earlier page of its tab showed at `url`, and
    /// shows it heading there at once, so its owner does not load it anew.
    public void Restoring(string url) => shown = shown with { PendingUrl = url };

    /// The page takes on the history its tab's last page held, restoring
    /// that page's engine's history when `restores`.
    public void Resume(PageHistory history, bool restores) {
        History = history;
        history.Reopen(Engine.Kind, restores);
    }

    /// Whether a window shows the page now. A page leaving the screen is
    /// stamped at `now`; one already off screen keeps its stamp. Answers
    /// whether the page came back on screen, which a page ending a video's
    /// Picture in Picture reads.
    public bool Seen(bool isShown, DateTimeOffset now) {
        var returned = isShown && HiddenSince is not null;
        HiddenSince = isShown ? null : HiddenSince ?? now;
        return returned;
    }

    /// The engine reported what the page shows now.
    public void Show(PageSnapshot snapshot) => shown = snapshot;

    /// The engine reported an icon for the document. Answers whether its tab
    /// may wear it now: the page has a tab and the document is recorded, so
    /// the tab shows it. Otherwise the record adopts it.
    public bool ShowIcon(PageIcon icon) {
        Icon = icon;
        return TabId is not null && isRecorded;
    }

    #endregion

    #region Actions - Crashes

    /// The page's renderer stopped, for the engine's reason `domain` and
    /// `code`. Answers whether the engine brings the page back now. A page a
    /// window shows reloads at once while the recovery budget lasts, and past
    /// it shows the failure until the person asks for the page again. A page
    /// nobody sees spends none of the budget and shows no failure, because the
    /// system most often ends a renderer nobody sees to take its memory back:
    /// it comes back once it is shown.
    public bool Crash(bool isShown, string domain, long code) {
        if (isShown) return Stopped(domain, code);
        stoppedUnseen = (domain, code);
        shown = shown with { PendingUrl = null, IsLoading = false };
        return false;
    }

    /// A window shows the page that stopped while nobody saw it. Bringing it
    /// back counts against the budget as a stop in view does, so a page that
    /// stops again once shown still ends at the failure. Answers whether its
    /// engine brings it back.
    public bool Recover() {
        if (stoppedUnseen is not var (domain, code)) return false;
        stoppedUnseen = null;
        return Stopped(domain, code);
    }

    /// The renderer of a page a window shows stopped: it reloads while the
    /// budget lasts, and past it the page shows the failure.
    private bool Stopped(string domain, long code) {
        crashes++;
        if (ProcessRecoveryAction.For(crashes).Reloads) return true;
        failure = new PageFailure(NavigationError.WebContentProcessStopped, shown.Url, ReplacedDocument: true, domain, code);
        shown = shown with { PendingUrl = null, IsLoading = false };
        return false;
    }

    #endregion
}
