using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Setup as the core walks a person through it: where each entry opens and
/// where Back and Next lead on each platform, the queue of browsers it imports
/// in turn, finishing, which applies the manual setup and opens the Getting
/// Started guide only in an unlocked first Space, and whether the device has
/// completed setup, which the device store adopts once and keeps.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void EachEntryOpensOnItsStepAndBackLeadsWhereThePlatformSays() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);

        // Set up by hand from the app, Back closes setup rather than import.
        var manual = device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup));
        Assert.Equal((SetupStep.ManualSetup, (SetupStep?)null), (Flowing(manual).Step, Flowing(manual).BackStep));
        Assert.Contains(manual, change => change is SetupDraftChanged { Draft: not null });
        // A Mac asks which look its Spaces wear on the way from the welcome to import.
        var guided = Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun)));
        Assert.Equal((SetupStep.Welcome, SetupStep.Look, (SetupStep?)null), (guided.Step, guided.NextStep, guided.BackStep));
        var look = Flowing(device.Send(new ShowSetupStep(SetupStep.Look)));
        Assert.Equal((SetupStep.ImportBrowser, SetupStep.Welcome), (look.NextStep, look.BackStep));
        Assert.Equal(SetupStep.Look, Flowing(device.Send(new ShowSetupStep(SetupStep.ImportBrowser))).BackStep);
        var skipped = Flowing(device.Send(new ContinueImport()));
        Assert.Equal((SetupStep.ManualSetup, SetupStep.ImportBrowser), (skipped.Step, skipped.BackStep));
        Assert.Null(Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.ImportBrowser))).BackStep);
        Assert.IsType<PersistentWorkspaceRequired>(Assert.Throws<Rejected>(() =>
            device.Send(new StartSetup(device.Attach(session, WorkspaceKind.Private), SetupEntry.FirstRun))).Rejection);

        // A phone goes from the welcome to setting up Spaces, and back.
        using var phone = new CrestApp(new AppConfiguration(null, DevicePlatform.Mobile));
        var workspace = TestWorkspaces.Open(phone, session);
        Assert.Equal(SetupStep.ManualSetup, Flowing(phone.Send(new StartSetup(workspace, SetupEntry.FirstRun))).NextStep);
        Assert.Equal(SetupStep.Welcome, Flowing(phone.Send(new ShowSetupStep(SetupStep.ManualSetup))).BackStep);
    }

    [Fact]
    public void TheChosenLookDressesEverySpaceSetupMakesAndEachOneAnImportBringsInNew() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var seeded = device.Authority.Current.Spaces[0];
        static (SpaceThemeMode, SpaceIconStyle) Worn(SpaceCustomization customization) =>
            (customization.Branding.ThemeMode, customization.Branding.IconStyle);
        var heraldic = (SpaceThemeMode.Banner, SpaceIconStyle.LayeredCrest);
        var modern = (SpaceThemeMode.Gradient, SpaceIconStyle.SimpleSymbol);

        // Setup opens in Crest's own look; the person may choose the modern one.
        Assert.Equal(SetupLook.Heraldic, Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun))).Look);
        Assert.Equal(SetupLook.Modern, Flowing(device.Send(new ChooseSetupLook(SetupLook.Modern))).Look);

        // A new Space of the manual setup wears it, and so does the first
        // launch's disposable Space, which the person has not made theirs.
        device.Send(new ShowSetupStep(SetupStep.ImportBrowser));
        var started = Drafted(device.Send(new ContinueImport()));
        Assert.Equal([(seeded.Id, modern)], started.Spaces.Select(space => (space.SpaceId, Worn(space.Customization))));
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces[1];
        Assert.Equal((modern, seeded.Settings.Name), (Worn(added.Customization), started.Spaces[0].ShownName));
        // Choosing another look restyles the setup the device holds: a new
        // Space not yet edited takes the look a new Space gets, the disposable
        // one keeps its colors in the new mode.
        var restyled = Drafted(device.Send(new ChooseSetupLook(SetupLook.Heraldic)));
        Assert.Equal(heraldic, Worn(restyled.Spaces[0].Customization));
        Assert.Equal(SpaceAccent.Orange.House, restyled.Spaces[1].Customization.Branding);

        // A Space an import brings in new wears it; one joining an existing
        // Space takes that Space's look.
        device.Send(new ChooseSetupLook(SetupLook.Modern));
        device.Send(new ShowSetupStep(SetupStep.ImportBrowser));
        device.Send(new OfferImportSources([ImportSource.Arc]));
        device.Send(new ToggleImportSource(ImportSource.Arc));
        device.Send(new ContinueImport());
        var review = Flowing(device.Send(new ReviewImport(ImportSource.Arc,
            ReadSpaces(ImportedSpace("Arc", ImportedTab("https://arc.example/"))), []))).Review!;
        Assert.Equal(modern, Worn(review.Spaces[0].Customization));
    }

    [Fact]
    public void SetupImportsEachChosenBrowserInTurnThenSetsUpSpacesByHand() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        device.Send(new OfferImportSources([ImportSource.Arc, ImportSource.Chrome]));
        device.Send(new ToggleImportSource(ImportSource.Chrome));
        var chosen = Flowing(device.Send(new ToggleImportSource(ImportSource.Arc)));
        Assert.Equal([ImportSource.Arc, ImportSource.Chrome], chosen.Selected);

        var reading = Flowing(device.Send(new ContinueImport()));
        Assert.Equal((SetupPhase.Reading, ImportSource.Arc), (reading.Phase, reading.Source));
        Assert.IsType<SetupBusy>(Assert.Throws<Rejected>(() => device.Send(new ToggleImportSource(ImportSource.Arc))).Rejection);
        var failed = Flowing(device.Send(new FailImport(ImportSource.Arc, SetupFailureReason.Read, "Unreadable")));
        Assert.Equal((SetupStep.ImportBrowser, SetupPhase.Idle, new SetupFailure(SetupFailureReason.Read, ImportSource.Arc, "Unreadable")),
            (failed.Step, failed.Phase, failed.Failure));

        foreach (var source in new[] { ImportSource.Arc, ImportSource.Chrome }) {
            if (source == ImportSource.Arc) device.Send(new ContinueImport());
            // A read setup no longer waits for changes nothing.
            Assert.Empty(device.Send(new ReviewImport(ImportSource.Safari, [], [])));
            var reviewing = Flowing(device.Send(new ReviewImport(source, ReadSpaces(ImportedSpace(source.Title,
                ImportedTab($"https://{source.Name}.example/"))), [])));
            Assert.Equal((SetupStep.Review, SetupPhase.Reviewing), (reviewing.Step, reviewing.Phase));
            device.Send(new BeginImportCommit());
            device.Send(new ImportReviewedSpaces(device.Workspace, window));
            var next = Flowing(device.Send(new FinishImportCommit(PasswordCount: 0)));
            if (source == ImportSource.Arc) {
                Assert.Equal((SetupPhase.Reading, ImportSource.Chrome), (next.Phase, next.Source));
                Assert.Equal([ImportSource.Chrome], next.Selected);
            } else Assert.Equal((SetupStep.ManualSetup, SetupPhase.Idle), (next.Step, next.Phase));
        }
        Assert.Equal(["Arc", "Chrome"], device.Authority.Current.Spaces.Select(space => space.Settings.Name));
    }

    [Fact]
    public void FinishingOpensTheGuideOnlyInAnUnlockedFirstSpaceAndAppliesTheManualSetupWithIt() {
        var session = GuardedSession();
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var locked = device.Authority.Current.Spaces[0];
        device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun));
        device.Send(new ShowSetupStep(SetupStep.ManualSetup));
        device.Send(new AddSetupSpace());
        // The ready page after the manual setup leads back to it, and finishing from it applies the setup.
        Assert.Equal(SetupStep.ManualSetup, Flowing(device.Send(new ShowSetupStep(SetupStep.Complete))).BackStep);
        var before = device.Authority.Current;

        Assert.Equal(new GuideSpaceLocked(locked.Id), Assert.Throws<Rejected>(() => device.Send(new FinishSetup(window))).Rejection);
        Assert.Same(before, device.Authority.Current);

        TestGrants.Unlock(device.Send, device.Workspace, locked.Id);
        var finished = device.Send(new FinishSetup(window));
        Assert.Contains(new SetupCompletedChanged(true), finished);
        Assert.Contains(new SetupFinished(device.Workspace, locked.Id), finished);
        Assert.Contains(new SetupDraftChanged(null), finished);
        Assert.Equal(2, device.Authority.Current.Spaces.Count);
        var complete = Flowing(finished);
        Assert.Equal((SetupStep.Complete, new SetupSummary(IsImport: false, 0, 0, SpaceCount: 1)), (complete.Step, complete.Summary));
    }

    [Fact]
    public void SetupHoldsTheLaunchBackUntilItFinishesOnADeviceThatNeverCompletedItOrWhenForced() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var forced = LaunchEnvironment.Installed with { ForcesDesktopSetup = true };
        SetupEntry? Gate(LaunchEnvironment environment) => device.Query(new LaunchSetup(environment)).Setup;
        StartupBehavior Startup(DevicePlatform platform) =>
            device.Query(new LaunchPlan(device.Workspace, platform, LaunchEnvironment.Installed)).Startup;

        // Setup holds the Mac's first window back, which then shows the tab the
        // person left; on a phone it covers the browser, which opens as chosen.
        Assert.Equal(SetupEntry.FirstRun, Gate(LaunchEnvironment.Installed));
        Assert.Equal(SetupEntry.FirstRun, device.Query(new LaunchWindows(LaunchEnvironment.Installed)).Setup);
        Assert.Equal(StartupBehavior.LastActiveTab, Startup(DevicePlatform.Desktop));
        Assert.Equal(StartupBehavior.ShowStartPage, Startup(DevicePlatform.Mobile));

        // A device that completed setup opens straight away, unless the launch
        // forces setup on its platform.
        device.Send(new AdoptSetupCompletion(Completed: true));
        Assert.Null(Gate(LaunchEnvironment.Installed));
        Assert.Equal(StartupBehavior.ShowStartPage, Startup(DevicePlatform.Desktop));
        Assert.Equal(SetupEntry.FirstRun, Gate(forced));
        Assert.Null(Gate(LaunchEnvironment.Installed with { ForcesMobileSetup = true }));

        // Finishing setup opens the gate for the rest of the run, whatever the launch forced.
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        device.Send(new FinishSetup(window));
        Assert.Null(Gate(forced));
    }

    [Fact]
    public void CompletionIsAdoptedOnceAndKeptInTheDeviceStore() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        Guid first = SpaceId(document["spaces"]![0]!);
        using (var app = new CrestApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            Assert.Contains(new SetupCompletedChanged(false), app.Send(new AdoptSetupCompletion(Completed: false)));
            var fresh = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((true, false), (fresh.OpensGuide, fresh.OpensCrestFromWelcome));
            var finished = app.Send(new FinishSetup(Guid.NewGuid()));
            Assert.Contains(new SetupCompletedChanged(true), finished);
            Assert.Contains(new SetupFinished(workspace, first), finished);
        }
        using (var app = new CrestApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            // The store adopted once: what an installed release kept no longer counts.
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: false)));
            var again = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((false, true), (again.OpensGuide, again.OpensCrestFromWelcome));
            Assert.True(Flowing(app.Send(new StartSetup(workspace, SetupEntry.Rerun))).OpensGuide);
        }
        using var adopting = new StorageDirectory();
        using (var app = new CrestApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop))) {
            app.Send(Adoption(document));
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: true)));
        }
        using var reopened = new CrestApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop));
        Assert.Contains(new SetupCompletedChanged(true), reopened.Send(new AdoptSetupCompletion(Completed: false)));
    }
}
