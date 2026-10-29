using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class RetentionBoundaryTests {
    [Fact]
    public void RetentionAndExplicitDeletionKeepTheirDifferentBoundaryRules() {
        // Retention excludes an exact cutoff and future records. Explicit
        // deletion includes its start and excludes its end. The
        // `SweepExpiredRecords` and `RemoveHistoryRange` intents apply this rule.
        Assert.Equal([0], DataRetention.Expired([9, 10, 11, 21], 20, 10));
    }
}
