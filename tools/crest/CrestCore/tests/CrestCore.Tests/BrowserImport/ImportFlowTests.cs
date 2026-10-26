using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Imports process each selected browser in order, with failed reads retried safely.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ImportProcessesEachChosenBrowserInTurnAndPreservesTheResults() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        device.Send(new StartBrowserImport(device.Workspace));
        device.Send(new OfferImportSources([ImportSource.Arc, ImportSource.Chrome]));
        device.Send(new ToggleImportSource(ImportSource.Chrome));
        var chosen = Flowing(device.Send(new ToggleImportSource(ImportSource.Arc)));
        Assert.Equal([ImportSource.Arc, ImportSource.Chrome], chosen.Selected);

        var reading = Flowing(device.Send(new ContinueImport()));
        Assert.Equal((ImportPhase.Reading, ImportSource.Arc), (reading.Phase, reading.Source));
        Assert.IsType<BrowserImportBusy>(Assert.Throws<Rejected>(() => device.Send(new ToggleImportSource(ImportSource.Arc))).Rejection);
        var failed = Flowing(device.Send(new FailImport(ImportSource.Arc, ImportFailureReason.Read, "Unreadable")));
        Assert.Equal((ImportStep.ImportBrowser, ImportPhase.Idle, new ImportFailure(ImportFailureReason.Read, ImportSource.Arc, "Unreadable")),
            (failed.Step, failed.Phase, failed.Failure));

        foreach (var source in new[] { ImportSource.Arc, ImportSource.Chrome }) {
            if (source == ImportSource.Arc) device.Send(new ContinueImport());
            // A read setup no longer waits for changes nothing.
            Assert.Empty(device.Send(new ReviewImport(ImportSource.Safari, [], [])));
            var reviewing = Flowing(device.Send(new ReviewImport(source, ReadSpaces(ImportedSpace(source.Title,
                ImportedTab($"https://{source.Name}.example/"))), [])));
            Assert.Equal((ImportStep.Review, ImportPhase.Reviewing), (reviewing.Step, reviewing.Phase));
            device.Send(new BeginImportCommit());
            device.Send(new ImportReviewedSpaces(device.Workspace, window));
            var next = Flowing(device.Send(new FinishImportCommit()));
            if (source == ImportSource.Arc) {
                Assert.Equal((ImportPhase.Reading, ImportSource.Chrome), (next.Phase, next.Source));
                Assert.Equal([ImportSource.Chrome], next.Selected);
            } else Assert.Equal((ImportStep.Complete, ImportPhase.Idle), (next.Step, next.Phase));
        }
        Assert.Equal(["Arc", "Chrome"], device.Authority.Current.Spaces.Select(space => space.Settings.Name));
    }

}
