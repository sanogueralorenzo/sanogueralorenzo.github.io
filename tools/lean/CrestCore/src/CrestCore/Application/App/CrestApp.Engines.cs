using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    /// The engine bindings pages open on.
    private readonly Engines engines = new();
    internal Engines Engines => engines;

    /// Commands issued and not yet delivered, oldest first.
    private readonly Queue<(Engine Engine, EngineCommand Command)> undelivered = [];
    private readonly Lock deliveryGate = new();

    /// A call is handing commands to bindings. Any other call, on this thread
    /// inside a binding or on another, only adds to the queue.
    private bool delivering;

    /// The engines as the core last published them.
    private EngineRoster publishedEngines = EngineRoster.Unregistered;

    #endregion

    #region Actions - Engines

    /// Registers an engine binding. The core hands it commands through `run`,
    /// in the order it issued them, never while it holds a lock. Throws
    /// `Rejected` when the engine lacks a required capability, is already
    /// registered, or asks to be the default beside another default.
    public Engine RegisterEngine(EngineRegistration registration, Action<EngineCommand> run) {
        Engine engine;
        lock (gate) {
            engine = engines.Register(registration, run);
            PublishEngines(Announce);
        }
        WakeIfOwed();
        return engine;
    }

    /// Removes a binding. Commands still waiting for it are dropped.
    public void UnregisterEngine(Engine engine) {
        lock (gate) {
            engines.Unregister(engine);
            PublishEngines(Announce);
        }
        WakeIfOwed();
    }

    /// The engines as they stand, and what they offer with the pages open now.
    /// The caller holds the lock.
    internal EngineRoster RegisteredEngines() => engines.Roster(pages.HostingEngines);

    /// Hands `publish` the engines when they changed since the core last
    /// published them: one registered or went away, or what they offer
    /// changed because a page opened on an engine no page used or an engine's
    /// last page went. The shortcut bindings follow when the commands they
    /// offer changed. The caller holds the lock.
    internal void PublishEngines(Action<Change> publish) {
        var current = RegisteredEngines();
        if (current.SameAs(publishedEngines)) return;
        var before = Engines.OfferedCommands(publishedEngines);
        publishedEngines = current;
        publish(new EnginesChanged(current));
        if (device.ShortcutsAfter(before, Engines.OfferedCommands(current)) is { } changed) publish(changed);
    }

    /// Applies what an engine saw happen to one of its pages. A report is
    /// never refused; one about a page the core no longer knows changes
    /// nothing. What it changed arrives through the next drain, whole and
    /// before anything a later call publishes, and commands it caused, such as
    /// bringing back a page whose renderer stopped, are delivered after it,
    /// never on its stack when it arrives inside a delivery.
    public void Report(Engine engine, EngineEvent report) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(report);
        lock (gate) {
            var changes = new ChangeFeed();
            report.Route(this, engine, changes);
            foreach (var change in changes.Published) Announce(change);
        }
        WakeIfOwed();
        WakeForRequestedTurn();
        Deliver();
    }

    /// A report that moved a page to another engine, or offered one that may
    /// be the first a registered engine hosts, changes what the engines offer,
    /// a tab group follows the pages and folders that show it, and what a page
    /// that went had asked no longer waits. The caller holds the lock.
    internal void AfterPageReport(ChangeFeed changes) {
        pages.ReconcileGroups(Issue);
        PublishEngines(changes.Publish);
        prompts.Prune(changes);
        closePreparations.Prune(changes, Issue);
    }

    /// Answers what an engine asks about one of its pages while the engine
    /// waits, from the state as it stands, changing nothing.
    public TAnswer Ask<TAnswer>(Engine engine, EngineQuestion<TAnswer> question) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(question);
        lock (gate) return question.Answer(this, engine);
    }

    #endregion

    #region Actions - Delivery

    /// Queues a command for delivery once the core lets go of its lock.
    internal void Issue(Engine engine, EngineCommand command) {
        lock (deliveryGate) undelivered.Enqueue((engine, command));
    }

    /// Hands every queued command to its binding, oldest first, unless a
    /// delivery is already under way: that one delivers what was added. A
    /// binding that sends an intent or a report while it runs a command adds to
    /// the queue, and the queue is never entered twice.
    private void Deliver() {
        lock (deliveryGate) {
            if (delivering) return;
            delivering = true;
        }
        while (true) {
            (Engine Engine, EngineCommand Command) next;
            lock (deliveryGate) {
                if (!undelivered.TryDequeue(out next)) {
                    delivering = false;
                    return;
                }
            }
            try {
                next.Engine.Run(next.Command);
            } catch {
                lock (deliveryGate) delivering = false;
                throw;
            }
        }
    }

    #endregion
}
