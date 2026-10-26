using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class DownloadLedgerTests {
    private static readonly Guid Work = Guid.NewGuid(), Personal = Guid.NewGuid();
    private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly TimeSpan Day = TimeSpan.FromDays(1);

    private static DateTimeOffset At(double seconds) => Epoch.AddSeconds(seconds);

    private static Guid Begin(DownloadLedger ledger, Guid profile, string filename = "file.pdf", DateTimeOffset? createdAt = null,
        bool acknowledged = false) => ledger.Begin(Guid.NewGuid(), profile, filename, createdAt ?? Epoch, acknowledged).Id;

    [Fact]
    public void ExpiryIsProfileScopedStrictAndNeverRemovesLiveTransfers() {
        var ledger = new DownloadLedger();
        DateTimeOffset now = Epoch + 1_000 * Day;
        TimeSpan lifetime = 30 * Day;
        var expired = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        ledger.Finish(expired, null);
        var boundary = Begin(ledger, Work, createdAt: now - lifetime);
        ledger.Cancel(boundary, "Canceled.");
        var active = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        var blocked = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        ledger.BlockAutomaticDownload(blocked);
        var otherProfile = Begin(ledger, Personal, createdAt: Epoch);
        ledger.Finish(otherProfile, null);

        var removed = ledger.RemoveExpired([new(Work, lifetime)], now);

        Assert.Equal([blocked, expired], removed);
        Assert.Equal([otherProfile, active, boundary], ledger.Items.Select(item => item.Id));
    }

    [Fact]
    public void TheShortestRetentionOfSpacesSharingAProfileWinsAndForeverKeepsRecords() {
        var ledger = new DownloadLedger();
        DateTimeOffset now = Epoch + 1_000 * Day;
        var weekOld = Begin(ledger, Work, createdAt: now - 8 * Day);
        ledger.Finish(weekOld, null);
        var ancient = Begin(ledger, Personal, createdAt: Epoch);
        ledger.Finish(ancient, null);

        Assert.Empty(ledger.RemoveExpired([new(Work, 30 * Day), new(Work, null), new(Personal, null)], now));
        Assert.Equal([weekOld], ledger.RemoveExpired([new(Work, 30 * Day), new(Work, 7 * Day), new(Work, null)], now));
        Assert.Equal([ancient], ledger.Items.Select(item => item.Id));
        Assert.IsType<InvalidRetentionLifetime>(Assert.Throws<Rejected>(() => ledger.RemoveExpired([new(Work, -Day)], now)).Rejection);
    }
}
