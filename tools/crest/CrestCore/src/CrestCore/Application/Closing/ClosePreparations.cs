using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares to close pages, windows or the app. Each page that would close and
/// that its engine holds is asked in turn whether it may go, one page at a
/// time; the first that asks to stay ends the preparation not allowed. A page
/// that goes meanwhile has nothing to ask, and one that shows another document
/// after it agreed voids the answer. Quitting with downloads in progress then
/// asks the person, and a quit allowed tells the device, whose windows then
/// stay the ones the next launch reopens.
internal sealed class ClosePreparations(Device device, Pages pages, Downloads downloads, DataDeletions deletions, IIdSource ids) {
    #region Types

    internal sealed class Preparation(Guid requestId, bool quits, IEnumerable<Guid> pageIds, Action<bool, ChangeFeed>? completion) {
        public Action<bool, ChangeFeed>? Completion { get; } = completion;
        public Guid RequestId { get; } = requestId;
        public bool Quits { get; } = quits;
        /// The pages still to ask, in order.
        public Queue<Guid> Pending { get; } = new(pageIds);
        /// Each page asked, with how many documents it had shown when asked.
        public Dictionary<Guid, long> Asked { get; } = [];
        /// The page whose answer the preparation waits for.
        public Guid? Awaiting { get; set; }
        /// The question about downloads in progress, while it waits.
        public Guid? PromptId { get; set; }
    }

    #endregion

    #region Variables

    private Preparation? underway;

    /// The preparation under way, or null.
    internal Preparation? Underway => underway;

    /// The question about downloads in progress the preparation under way
    /// waits for, or null.
    internal Guid? QuitPromptId => underway?.PromptId;

    /// The pages this device hosts, which a preparation asks.
    internal Pages Pages => pages;

    /// This device's windows and the workspaces they show.
    internal Device Device => device;

    /// Erasing what the engines keep for a profile, which a Space's deletion
    /// waits on.
    internal DataDeletions DataDeletions => deletions;

    #endregion

    #region Actions - Intents

    /// Runs one close intent, publishing what it changed and handing the engine
    /// commands it causes to `issue`.
    public void Handle(CloseIntent intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) => intent.Apply(this, changes, issue);

    /// Begins preparing to close `pageIds`, and to quit when `quits`. A close
    /// with no page to ask is ready at once, even while another preparation is
    /// under way; any other is refused with `ClosePreparationUnderway` then.
    internal void Start(Guid requestId, bool quits, IEnumerable<Guid> pageIds, ChangeFeed changes, Action<Engine, EngineCommand> issue,
        Action<bool, ChangeFeed>? completion = null) {
        var closing = pageIds.Distinct().ToList();
        if (!quits && closing.All(pageId => Asking(pageId) is null)) {
            if (completion is not null) completion(true, changes);
            else changes.Publish(new CloseReady(requestId, Allowed: true));
            return;
        }
        if (underway is not null) throw new Rejected(new ClosePreparationUnderway(underway.RequestId));
        underway = new(requestId, quits, closing, completion);
        Advance(changes, issue);
    }

    #endregion

    #region Actions - Engines

    /// Moving engines discards the old document. Its normal before-unload
    /// decision must finish first, and a canceled or stale move changes no
    /// site preference. A page that moved, closed or lost access while the
    /// question was open never moves from this answer.
    internal void Move(Page page, Engine engine, string? address, RehostReason reason, bool remembersSite, PageTurn turn) {
        var previous = page.Engine;
        long document = page.Documents;
        var origin = address is null ? null : new WebAddress(address).Origin;
        var siteEngine = origin is null ? null : device.ChosenEngine(page.SpaceId, origin);
        Start(ids.Next(), quits: false, [page.Id], turn.Changes, turn.Issue, (allowed, changes) => {
            if (!allowed || !ReferenceEquals(pages.Hosted(page.Id), page) || !ReferenceEquals(page.Engine, previous)
                || page.Documents != document || pages.Shown(page) is null)
                return;
            if (remembersSite && origin is not null) {
                if (device.ChosenEngine(page.SpaceId, origin) != siteEngine) return;
                device.Choose(page.SpaceId, origin, engine.Kind);
            }
            pages.Rehost(page, engine, address, reason, new PageTurn(changes, turn.Issue, this));
        });
    }

    /// Going back or forward to an entry another engine held discards the
    /// document the page shows, as a move does, so its before-unload decision
    /// finishes first. A canceled answer leaves the page where it is, and a
    /// page that moved, closed or showed another document while the question
    /// was open does not go.
    internal void Return(Page page, Guid entryId, PageTurn turn) {
        var previous = page.Engine;
        long document = page.Documents;
        Start(ids.Next(), quits: false, [page.Id], turn.Changes, turn.Issue, (allowed, changes) => {
            if (!allowed || !ReferenceEquals(pages.Hosted(page.Id), page) || !ReferenceEquals(page.Engine, previous)
                || page.Documents != document || pages.Shown(page) is null)
                return;
            pages.Return(page, entryId, new PageTurn(changes, turn.Issue, this));
        });
    }

    #endregion

    #region Actions - Reports

    /// The page the preparation waits for went, so it has nothing to answer.
    public void Prune(ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(changes);
        ArgumentNullException.ThrowIfNull(issue);
        if (underway?.Awaiting is not { } pageId || Asking(pageId) is not null) return;
        underway.Awaiting = null;
        Advance(changes, issue);
    }

    #endregion

    #region Actions - Rules

    /// Asks the next page that may still ask, or finishes: not allowed when a
    /// page that agreed shows another document since, and for a quit with
    /// downloads in progress, once the person answers.
    internal void Advance(ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var preparation = underway!;
        while (preparation.Pending.TryDequeue(out var pageId)) {
            if (Asking(pageId) is not { } page) continue;
            preparation.Awaiting = page.Id;
            preparation.Asked[page.Id] = page.Documents;
            issue(page.Engine, new CheckBeforeUnload(page.Id));
            return;
        }
        if (preparation.Asked.Any(asked => pages.Hosted(asked.Key) is { } page && page.Documents != asked.Value)) {
            Finish(allowed: false, changes);
            return;
        }
        int live = downloads.LiveCount;
        if (preparation.Quits && live > 0) {
            preparation.PromptId = ids.Next();
            changes.Publish(new QuitWithDownloadsAsked(preparation.PromptId.Value, preparation.RequestId, live));
            return;
        }
        Finish(allowed: true, changes);
    }

    internal void Finish(bool allowed, ChangeFeed changes) {
        var preparation = underway!;
        underway = null;
        if (preparation.Quits && allowed) device.AcceptQuit();
        if (preparation.PromptId is { } prompt) changes.Publish(new PromptSettled(prompt));
        if (preparation.Completion is { } completion) completion(allowed, changes);
        else changes.Publish(new CloseReady(preparation.RequestId, allowed));
    }

    /// A live page, which its engine can ask.
    private Page? Asking(Guid pageId) => pages.Hosted(pageId) is { } page && page.Phase == PagePhase.Live ? page : null;

    #endregion
}
