using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;
using Xunit.Abstractions;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A page's history across engines, walked through two simulated engines
    /// that keep native back and forward lists the way the real ones do:
    /// Chromium keeps its entries' identities when it restores its history,
    /// WebKit gives them new ones. After every step the core's history must
    /// show the entry the engine shows, list no entry twice, and agree with
    /// whether the page can go back or forward.
    public sealed class CrossEngineHistoryWalks(ITestOutputHelper output) {
        /// One simulated engine: each page's native history, and the histories
        /// its closed pages handed back.
        private sealed class NativeEngine(EngineKind kind, bool keepsIdentities) {
            public EngineKind Kind { get; } = kind;
            public bool KeepsIdentities { get; } = keepsIdentities;
            public Engine Engine { get; set; } = null!;
            public List<EngineCommand> Commands { get; } = [];
            public int Handled { get; set; }
            public Dictionary<Guid, (List<PageHistoryEntry> Entries, int Current)> Pages { get; } = [];
            public List<(List<PageHistoryEntry> Entries, int Current)> Kept { get; } = [];
            public bool Proceeds { get; set; } = true;
            public bool KeepsNothing { get; set; }

            public void Run(EngineCommand command) => Commands.Add(command);

            /// What the platform archives of `page`: its history as the engine
            /// saves it, which `Kept` brings back.
            public PageRestoreState Save(Guid page) {
                var (entries, current) = Pages[page];
                Kept.Add(([.. entries], current));
                return new PageRestoreState(entries[current].Url, BitConverter.GetBytes(Kept.Count - 1));
            }
        }

        /// The app with both engines and one tab's page, which the engines
        /// answer as their adapters would.
        private sealed class Browser : IDisposable {
            public CrestApp App { get; } = new();
            public NativeEngine Chromium { get; } = new(EngineKind.Chromium, keepsIdentities: true);
            public NativeEngine WebKit { get; } = new(EngineKind.WebKit, keepsIdentities: false);
            public Guid Workspace { get; set; }
            public Guid Window { get; } = Guid.NewGuid();
            public Guid Space { get; init; }
            public Guid Tab { get; init; }
            public Guid Page { get; set; }
            public List<string> Log { get; } = [];

            public Page Hosted => App.Pages.Hosted(Page)!;
            public NativeEngine Hosting => Hosted.Engine.Kind == EngineKind.Chromium ? Chromium : WebKit;

            public void Dispose() => App.Dispose();

            /// Lets both engines answer every command the core issued, until
            /// neither has one left.
            public void Settle() {
                for (int round = 0; round < 200; round++) {
                    bool answered = false;
                    foreach (var engine in new[] { Chromium, WebKit }) {
                        while (engine.Handled < engine.Commands.Count) {
                            answered = true;
                            Answer(engine, engine.Commands[engine.Handled++]);
                        }
                    }
                    if (!answered) {
                        App.Drain();
                        return;
                    }
                }
                throw new InvalidOperationException("The engines never settled.");
            }

            private void Answer(NativeEngine engine, EngineCommand command) {
                Log.Add($"{engine.Kind.Name} <- {command.GetType().Name}");
                switch (command) {
                    case CreatePage create:
                        engine.Pages[create.PageId] = ([], -1);
                        App.Report(engine.Engine, new PageCreated(create.PageId));
                        if (create.RestoreState is { } restore) Restore(engine, create.PageId, restore);
                        break;
                    case LoadPage load:
                        Navigate(engine, load.PageId, load.Url, load.EntryId);
                        break;
                    case GoToHistoryEntry go:
                        if (engine.Pages.TryGetValue(go.PageId, out var held)
                            && held.Entries.FindIndex(entry => entry.Id == go.EntryId) is var index and >= 0)
                            Go(engine, go.PageId, index);
                        break;
                    case ClosePage close:
                        if (!engine.Pages.Remove(close.PageId, out var closed)) break;
                        PageRestoreState? kept = null;
                        if (close.KeepsState && closed.Current >= 0 && !engine.KeepsNothing) {
                            engine.Kept.Add(([.. closed.Entries], closed.Current));
                            kept = new PageRestoreState(closed.Entries[closed.Current].Url, BitConverter.GetBytes(engine.Kept.Count - 1));
                        }
                        App.Report(engine.Engine, new PageClosed(close.PageId, kept));
                        break;
                    case CheckBeforeUnload check:
                        App.Report(engine.Engine, new BeforeUnloadAnswered(check.PageId, engine.Proceeds));
                        break;
                }
            }

            /// The engine brings back the history `restore` saved for `page`,
            /// as it does for a page the core restores or the platform restores
            /// from its archive.
            public void Restore(NativeEngine engine, Guid page, PageRestoreState restore) {
                var (entries, current) = engine.Kept[BitConverter.ToInt32(restore.State)];
                engine.Pages[page] = (engine.KeepsIdentities ? [.. entries] : [.. entries.Select(entry => entry with { Id = Guid.NewGuid() })],
                    current);
                Go(engine, page, current);
            }

            /// Whether `engine` still hosts `page` after a report that may have
            /// moved it.
            private bool Hosts(NativeEngine engine, Guid page) =>
                App.Pages.Hosted(page) is { } hosted && ReferenceEquals(hosted.Engine, engine.Engine) && engine.Pages.ContainsKey(page);

            /// The engine starts a navigation to `url`, a link or a load the
            /// core asked for, and commits it as a new entry.
            public void Navigate(NativeEngine engine, Guid page, string url, Guid? entryId = null) {
                App.Report(engine.Engine, new NavigationStarted(page, url, SameDocument: false));
                if (!Hosts(engine, page)) return;
                var (entries, current) = engine.Pages[page];
                List<PageHistoryEntry> next = [.. entries.Take(current + 1), new(entryId ?? Guid.NewGuid(), url, url)];
                engine.Pages[page] = (next, next.Count - 1);
                Committed(engine, page);
            }

            /// The engine goes to the entry at `index` of its own history.
            public void Go(NativeEngine engine, Guid page, int index) {
                App.Report(engine.Engine, new NavigationStarted(page, engine.Pages[page].Entries[index].Url, SameDocument: false));
                if (!Hosts(engine, page)) return;
                engine.Pages[page] = (engine.Pages[page].Entries, index);
                Committed(engine, page);
            }

            private void Committed(NativeEngine engine, Guid page) {
                var (entries, current) = engine.Pages[page];
                var url = entries[current].Url;
                Log.Add($"  {engine.Kind.Name} shows {Name(url)} of [{string.Join(", ", entries.Select(entry => Name(entry.Url)))}]");
                App.Report(engine.Engine, new NavigationCommitted(page, url, SameDocument: false));
                App.Report(engine.Engine, new PageStateChanged(page, PageSnapshot.Blank with { Url = url, Title = url }));
                App.Report(engine.Engine, new PageHistoryReported(page, [.. entries], current));
                App.Report(engine.Engine, new NavigationFinished(page, url, url));
            }
        }

        /// Pages named `site-…` share one site; any other name is a site of
        /// its own.
        private static string Address(string name) =>
            name.StartsWith("site-", StringComparison.Ordinal) ? $"https://site.example/{name}" : $"https://{name}.example/";

        private static string Name(string url) =>
            new Uri(url) is var uri && uri.AbsolutePath.Length > 1 ? uri.AbsolutePath[1..] : uri.Host.Split('.')[0];

        /// The fixture tab's page on Chromium, the default engine, showing
        /// `start`.
        private static Browser Open() {
            var fixture = SavedSession();
            var browser = new Browser { Space = fixture.Space, Tab = fixture.Tab, Page = Guid.NewGuid() };
            browser.Chromium.Engine = browser.App.RegisterEngine(
                new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true), browser.Chromium.Run);
            browser.WebKit.Engine = browser.App.RegisterEngine(
                new EngineRegistration(EngineKind.WebKit, [.. EngineCapability.Required, EngineCapability.ProtectedMedia], IsDefault: false),
                browser.WebKit.Run);
            browser.Workspace = TestWorkspaces.Open(browser.App, fixture.Document["session"]!);
            browser.App.Send(new OpenWindow(browser.Window, browser.Workspace, Saved: false, null, null, [], RestoresTabs: true));
            browser.App.Send(new OpenPage(browser.Page, browser.Workspace, browser.Space, browser.Tab, browser.Window));
            browser.Settle();
            browser.Navigate(browser.Chromium, browser.Page, Address("start"));
            browser.Settle();
            return browser;
        }

        private static void Follow(Browser browser, string name) {
            browser.Log.Add($"# link to {name}");
            browser.Navigate(browser.Hosting, browser.Page, Address(name));
            browser.Settle();
        }

        private static void Send(Browser browser, Intent intent) {
            browser.Log.Add($"# {intent}");
            browser.App.Send(intent);
            browser.Settle();
        }

        private static void Jump(Browser browser, string name) {
            var history = browser.App.Query(new PageHistoryEntries(browser.Page));
            Send(browser, new ShowHistoryEntry(browser.Page, history.Back.Concat(history.Forward).First(entry => Name(entry.Url) == name).Id));
        }

        private static void Move(Browser browser, EngineKind engine, bool remembersSite = false) =>
            Send(browser, new RehostPage(browser.Page, engine, remembersSite));

        /// The tab's page unloads, keeping its state, and the tab opens its
        /// next page, which loads the tab's address when nothing restored it.
        private static void Unload(Browser browser) {
            Send(browser, new ReleasePage(browser.Page, KeepsState: true));
            browser.Page = Guid.NewGuid();
            Send(browser, new OpenPage(browser.Page, browser.Workspace, browser.Space, browser.Tab, browser.Window));
            if (browser.Hosting.Pages[browser.Page].Current >= 0) return;
            var tab = browser.App.Workspace(browser.Workspace).Current.Spaces.Single(held => held.Id == browser.Space)
                .Tabs.Single(held => held.Id == browser.Tab);
            browser.Navigate(browser.Hosting, browser.Page, tab.Url!);
            browser.Settle();
        }

        /// The app quits and launches again. The platform archives the tab:
        /// its page's engine history, unless that engine keeps none, and the
        /// history the core answers for it. Nothing else survives. The tab
        /// hands that history back before its page opens, then restores the
        /// engine history when the page opens on that engine, or loads the
        /// tab's address.
        private static void Relaunch(Browser browser) {
            browser.Log.Add("# relaunch");
            var archive = browser.App.Query(new ArchivedPageHistory(browser.Page)).Archive;
            var engine = browser.Hosting;
            var saved = engine.KeepsNothing ? null : engine.Save(browser.Page);
            Send(browser, new ReleasePage(browser.Page, KeepsState: false));
            if (archive is not null) Send(browser, new RestoreTabHistory(browser.Workspace, browser.Space, browser.Tab, archive));
            browser.Page = Guid.NewGuid();
            Send(browser, new OpenPage(browser.Page, browser.Workspace, browser.Space, browser.Tab, browser.Window));
            if (ReferenceEquals(browser.Hosting, engine) && saved is not null) {
                browser.Restore(engine, browser.Page, saved);
            } else {
                var tab = browser.App.Workspace(browser.Workspace).Current.Spaces.Single(held => held.Id == browser.Space)
                    .Tabs.Single(held => held.Id == browser.Tab);
                browser.Navigate(browser.Hosting, browser.Page, tab.Url!);
            }
            browser.Settle();
        }

        /// The engine the page is on, what that engine shows, and what the
        /// history menus offer, nearest first.
        private void Expect(Browser browser, EngineKind engine, string shown, string[] back, string[] forward) {
            Check(browser, "");
            var history = browser.App.Query(new PageHistoryEntries(browser.Page));
            var (entries, current) = browser.Hosting.Pages[browser.Page];
            string actual = $"{browser.Hosted.Engine.Kind.Name} {Name(entries[current].Url)} "
                + $"[{string.Join(", ", history.Back.Select(entry => Name(entry.Url)))}] [{string.Join(", ", history.Forward.Select(entry => Name(entry.Url)))}]";
            string expected = $"{engine.Name} {shown} [{string.Join(", ", back)}] [{string.Join(", ", forward)}]";
            if (actual != expected) Fail(browser, $"Expected {expected}, found {actual}");
        }

        /// The core's history agrees with the engine the page is on: it shows
        /// the entry the engine shows, lists no entry twice, and can go back
        /// or forward exactly when its menus offer something.
        private void Check(Browser browser, string step) {
            var page = browser.Hosted;
            var history = browser.App.Query(new PageHistoryEntries(browser.Page));
            var (entries, current) = browser.Hosting.Pages[browser.Page];
            var listed = history.Back.Concat(history.Forward).Append(entries[current]).Select(entry => entry.Id).ToList();
            string? problem = page.History.Shown?.Id != entries[current].Id ? "the core's entry is not the one its engine shows"
                : page.Live.Url != entries[current].Url ? "the page's address is not the one its engine shows"
                : listed.Distinct().Count() != listed.Count ? "an entry is listed twice"
                : page.Live.CanGoBack != history.Back.Count > 0 || page.Live.CanGoForward != history.Forward.Count > 0
                    ? "going back or forward disagrees with the menus"
                : null;
            if (problem is not null) Fail(browser, step + problem);
        }

        private void Fail(Browser browser, string problem) {
            output.WriteLine(string.Join("\n", browser.Log));
            Assert.Fail(problem);
        }

        [Fact]
        public void APageMovedWithItsSiteGoesBackAndForwardOnTheEngineThatHeldEachEntry() {
            using var browser = Open();
            Follow(browser, "site-a");
            Follow(browser, "site-b");
            Follow(browser, "site-c");
            Move(browser, EngineKind.WebKit, remembersSite: true);
            Expect(browser, EngineKind.WebKit, "site-c", ["site-b", "site-a", "start"], []);

            // Going back replays history on Chromium, though the site now opens on WebKit.
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.Chromium, "site-b", ["site-a", "start"], ["site-c"]);
            Send(browser, new StepHistory(browser.Page, -1));
            Send(browser, new StepHistory(browser.Page, 1));
            Send(browser, new StepHistory(browser.Page, 1));
            Expect(browser, EngineKind.WebKit, "site-c", ["site-b", "site-a", "start"], []);

            // A new navigation follows the site's engine and leaves nothing ahead.
            Jump(browser, "site-a");
            Expect(browser, EngineKind.Chromium, "site-a", ["start"], ["site-b", "site-c"]);
            Follow(browser, "site-d");
            Expect(browser, EngineKind.WebKit, "site-d", ["site-a", "start"], []);
        }

        [Fact]
        public void MovingThePageItWentBackToKeepsWhatLayAheadOnTheEngineThatHeldIt() {
            using var browser = Open();
            Follow(browser, "a");
            Follow(browser, "b");
            Follow(browser, "c");
            Send(browser, new StepHistory(browser.Page, -1));
            Move(browser, EngineKind.WebKit);
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);
            Send(browser, new StepHistory(browser.Page, 1));
            Expect(browser, EngineKind.Chromium, "c", ["b", "a", "start"], []);
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);

            // A link to a site chosen for another engine is a new navigation.
            Send(browser, new StepHistory(browser.Page, -1));
            Send(browser, new ChooseSiteEngine(browser.Space, new WebAddress(Address("w")).Origin!, EngineKind.WebKit));
            Follow(browser, "w");
            Expect(browser, EngineKind.WebKit, "w", ["a", "start"], []);
        }

        [Fact]
        public void TheHistoryMenusReachEveryEntryOnEveryEngine() {
            using var browser = Open();
            Follow(browser, "a");
            Move(browser, EngineKind.WebKit);
            Follow(browser, "b");
            Move(browser, EngineKind.Chromium);
            Follow(browser, "c");
            Jump(browser, "start");
            Expect(browser, EngineKind.Chromium, "start", [], ["a", "b", "c"]);
            Jump(browser, "b");
            Expect(browser, EngineKind.Chromium, "b", ["a", "start"], ["c"]);
            Jump(browser, "a");
            Expect(browser, EngineKind.WebKit, "a", ["start"], ["b", "c"]);
            Jump(browser, "c");
            Expect(browser, EngineKind.Chromium, "c", ["b", "a", "start"], []);
        }

        [Fact]
        public void AnUnloadedTabReopensOnTheEngineItShowedWithItsHistory() {
            using var browser = Open();
            Follow(browser, "a");
            Follow(browser, "b");
            Move(browser, EngineKind.WebKit);
            Follow(browser, "c");
            Unload(browser);
            Expect(browser, EngineKind.WebKit, "c", ["b", "a", "start"], []);
            Send(browser, new StepHistory(browser.Page, -1));
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.Chromium, "a", ["start"], ["b", "c"]);

            // An engine that kept nothing loads the entry afresh, keeping the rest.
            browser.Chromium.KeepsNothing = true;
            Unload(browser);
            Expect(browser, EngineKind.Chromium, "a", ["start"], ["b", "c"]);
            Send(browser, new StepHistory(browser.Page, 1));
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);
        }

        [Fact]
        public void AHistoryComesBackAfterARelaunchOnEveryEngine() {
            using var browser = Open();
            Follow(browser, "a");
            Follow(browser, "b");
            Move(browser, EngineKind.WebKit);
            Follow(browser, "c");
            Relaunch(browser);
            Expect(browser, EngineKind.WebKit, "c", ["b", "a", "start"], []);
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.Chromium, "a", ["start"], ["b", "c"]);

            // A tab relaunched on Chromium after going back still goes forward to WebKit.
            Relaunch(browser);
            Expect(browser, EngineKind.Chromium, "a", ["start"], ["b", "c"]);
            Send(browser, new StepHistory(browser.Page, 1));
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);

            // An engine history the platform could not restore loads the entry afresh, keeping the rest.
            browser.WebKit.KeepsNothing = true;
            Relaunch(browser);
            Expect(browser, EngineKind.WebKit, "b", ["a", "start"], ["c"]);
            Send(browser, new StepHistory(browser.Page, -1));
            Expect(browser, EngineKind.Chromium, "a", ["start"], ["b", "c"]);
        }

        /// A truncated archive, and ones no engine could have written: an
        /// entry without a title, and a run that ends before it starts.
        [Fact]
        public void AnArchiveThisBuildCannotReadBringsNothingBack() {
            static byte[] Edited(byte[] archive, Action<JsonNode> edit) {
                var root = JsonNode.Parse(archive)!;
                edit(root);
                return Encoding.UTF8.GetBytes(root.ToJsonString());
            }
            Func<byte[], byte[]>[] unreadable = [
                archive => archive[..^4],
                archive => Edited(archive, root => root["runs"]![0]!["entries"]![0]!["title"] = null),
                archive => Edited(archive, root => {
                    var run = root["runs"]![0]!;
                    run["start"] = run["entries"]![1]!["id"]!.DeepClone();
                    run["boundary"] = run["entries"]![0]!["id"]!.DeepClone();
                }),
            ];
            foreach (var spoil in unreadable) {
                using var browser = Open();
                Follow(browser, "a");
                Follow(browser, "b");
                Move(browser, EngineKind.WebKit);
                var archive = browser.App.Query(new ArchivedPageHistory(browser.Page)).Archive!;
                Send(browser, new ReleasePage(browser.Page, KeepsState: false));
                Send(browser, new RestoreTabHistory(browser.Workspace, browser.Space, browser.Tab, spoil(archive)));
                browser.Page = Guid.NewGuid();
                Send(browser, new OpenPage(browser.Page, browser.Workspace, browser.Space, browser.Tab, browser.Window));
                browser.Navigate(browser.Hosting, browser.Page, Address("b"));
                browser.Settle();
                Expect(browser, EngineKind.Chromium, "b", [], []);
            }
        }

        /// Random walks of links, steps, menu jumps, moves with and without
        /// their site, unloads, relaunches, canceled leaves and native swipes, checked
        /// after every step.
        [Fact]
        public void RandomWalksKeepTheCoresHistoryInStepWithTheEngines() {
            for (int seed = 0; seed < 400; seed++) {
                var random = new Random(seed);
                using var browser = Open();
                for (int step = 0; step < 60; step++) {
                    var page = browser.Hosted;
                    var before = page.History.Shown!.Id;
                    var history = browser.App.Query(new PageHistoryEntries(browser.Page));
                    int roll = random.Next(100);
                    if (roll < 25) {
                        Follow(browser, random.Next(2) == 0 ? $"p{step}" : $"site-p{step}");
                    } else if (roll < 60) {
                        int offset = roll < 45 ? -1 : 1;
                        bool moves = offset < 0 ? page.Live.CanGoBack : page.Live.CanGoForward;
                        Send(browser, new StepHistory(browser.Page, offset));
                        if (moves && browser.Hosted.History.Shown!.Id == before) Fail(browser, $"seed {seed}, step {step}: a step went nowhere");
                    } else if (roll < 72) {
                        var reachable = history.Back.Concat(history.Forward).ToList();
                        if (reachable.Count > 0) Send(browser, new ShowHistoryEntry(browser.Page, reachable[random.Next(reachable.Count)].Id));
                    } else if (roll < 84) {
                        Move(browser, page.Engine.Kind == EngineKind.Chromium ? EngineKind.WebKit : EngineKind.Chromium,
                            remembersSite: random.Next(2) == 0);
                    } else if (roll < 88) {
                        browser.Chromium.KeepsNothing = random.Next(4) == 0;
                        browser.WebKit.KeepsNothing = random.Next(4) == 0;
                        Relaunch(browser);
                        browser.Chromium.KeepsNothing = browser.WebKit.KeepsNothing = false;
                    } else if (roll < 91) {
                        browser.Chromium.KeepsNothing = random.Next(4) == 0;
                        browser.WebKit.KeepsNothing = random.Next(4) == 0;
                        Unload(browser);
                        browser.Chromium.KeepsNothing = browser.WebKit.KeepsNothing = false;
                    } else if (roll < 95) {
                        browser.Hosting.Proceeds = false;
                        Send(browser, new StepHistory(browser.Page, -1));
                        browser.Hosting.Proceeds = true;
                    } else {
                        var (entries, current) = browser.Hosting.Pages[browser.Page];
                        int target = current + (random.Next(2) == 0 ? -1 : 1);
                        if (target >= 0 && target < entries.Count) {
                            browser.Log.Add("# native swipe");
                            browser.Go(browser.Hosting, browser.Page, target);
                            browser.Settle();
                        }
                    }
                    Check(browser, $"seed {seed}, step {step}: ");
                }
            }
        }
    }
}
