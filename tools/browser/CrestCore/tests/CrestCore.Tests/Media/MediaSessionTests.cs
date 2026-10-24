using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class MediaSessionTests {
    private static readonly MediaSessionIdentity Fresh = new(false, null, null, false, null);

    private static readonly MediaSessionAction[] Transport = [MediaSessionAction.Play, MediaSessionAction.Pause];

    private static MediaSessionEvent Report(ulong sequence, MediaPlaybackState playback = MediaPlaybackState.Playing,
        bool active = true, bool invalidated = false, bool muted = false, MediaSessionAction[]? actions = null) =>
        new(sequence, invalidated, active, playback, muted, actions ?? Transport);

    private static MediaSessionEventDecision Decide(MediaSessionEvent report, MediaSessionIdentity identity, int retained, ulong next) =>
        new MediaSessionReport(report, identity, retained, next).Decision;

    private static MediaSessionArbitration Arbitrate(IReadOnlyList<MediaSessionEntry> sessions) => new MediaSessionOrder(sessions).Arbitration;

    [Fact]
    public void StaleAndRetiredReportsChangeNothing() {
        var seen = Fresh with { LastSequence = 4, Ordinal = 2 };
        Assert.False(Decide(Report(4), seen, 10, 7).Accepted);
        Assert.False(Decide(Report(3), seen, 10, 7).Accepted);
        Assert.False(Decide(Report(9), seen with { IsRetired = true }, 10, 7).Accepted);
        Assert.False(Decide(Report(0), Fresh, 10, 7).Accepted);
        Assert.True(Decide(Report(5), seen, 10, 7).Accepted);
    }

    [Fact]
    public void APublishedDocumentKeepsItsOrdinalAndSupersedesItsTabSiblings() {
        var first = Decide(Report(1), Fresh, 0, 7);
        Assert.Equal(MediaSessionDisposition.Publish, first.Disposition);
        Assert.True(first.SupersedesTabSiblings);
        Assert.Equal(7UL, first.Ordinal);
        Assert.Equal(8UL, first.NextOrdinal);

        var update = Decide(Report(2), Fresh with { LastSequence = 1, Ordinal = 7 }, 1, 8);
        Assert.Equal(7UL, update.Ordinal);
        Assert.Equal(8UL, update.NextOrdinal);
    }

    [Fact]
    public void InvalidationRetiresAndAnInactiveSessionOnlyWithdrawsItsCard() {
        var retired = Decide(Report(2, invalidated: true), Fresh with { LastSequence = 1, Ordinal = 3 }, 1, 4);
        Assert.Equal(MediaSessionDisposition.Retire, retired.Disposition);
        Assert.False(retired.SupersedesTabSiblings);
        var cleared = Decide(Report(2, active: false), Fresh with { LastSequence = 1, Ordinal = 3 }, 1, 4);
        Assert.Equal(MediaSessionDisposition.Clear, cleared.Disposition);
        Assert.Null(cleared.Ordinal);
        Assert.Equal(4UL, cleared.NextOrdinal);
    }

    [Fact]
    public void OnlyMediaWithPlaybackControlsTakesACard() {
        MediaSessionDisposition Shown(MediaSessionEvent report, MediaSessionIdentity identity) =>
            Decide(report, identity, 1, 8).Disposition;

        // A notification chime: the engine's session plays, but offers no controls.
        var chime = Decide(Report(1, actions: []), Fresh, 0, 7);
        Assert.Equal(MediaSessionDisposition.Clear, chime.Disposition);
        Assert.Null(chime.Ordinal);
        Assert.Equal(7UL, chime.NextOrdinal);
        Assert.Equal(MediaSessionDisposition.Clear, Shown(Report(1, actions: [MediaSessionAction.NextTrack]), Fresh));
        Assert.Equal(MediaSessionDisposition.Clear, Shown(Report(1, muted: true, actions: []), Fresh));

        Assert.Equal(MediaSessionDisposition.Publish, Shown(Report(1), Fresh));
        Assert.Equal(MediaSessionDisposition.Publish,
            Shown(Report(1, MediaPlaybackState.Paused, actions: [MediaSessionAction.Play]), Fresh));

        // Muting the shown card's page may take its controls away; the card stays to unmute it.
        var shown = Fresh with { LastSequence = 1, Ordinal = 7, PreviousPlayback = MediaPlaybackState.Playing };
        Assert.Equal(MediaSessionDisposition.Publish, Shown(Report(2, muted: true, actions: []), shown));
        Assert.Equal(MediaSessionDisposition.Clear, Shown(Report(2, actions: []), shown));
    }

    [Fact]
    public void AHiddenCardReturnsOnlyWhenPlaybackStartsAfresh() {
        var hidden = Fresh with { LastSequence = 1, Ordinal = 1, IsDismissed = true, PreviousPlayback = MediaPlaybackState.Paused };
        Assert.True(Decide(Report(2), hidden, 1, 2).ClearsDismissal);
        Assert.False(Decide(Report(2, MediaPlaybackState.Paused), hidden, 1, 2).ClearsDismissal);
        Assert.False(Decide(Report(2),
            hidden with { PreviousPlayback = MediaPlaybackState.Playing }, 1, 2).ClearsDismissal);
        Assert.True(Decide(Report(2), hidden with { PreviousPlayback = null }, 1, 2).ClearsDismissal);
    }

    [Fact]
    public void RememberedIdentitiesStayWithinTheirWindow() {
        const int limit = MediaSessionReport.MaximumRetainedIdentities;
        Assert.Equal(0, Decide(Report(1), Fresh, limit - 1, 1).EvictOldest);
        Assert.Equal(1, Decide(Report(1, invalidated: true), Fresh, limit, 1).EvictOldest);
        Assert.Equal(0, Decide(Report(2), Fresh with { LastSequence = 1 }, limit, 1).EvictOldest);
    }

    [Fact]
    public void SessionsAreShownInFirstPublishedOrderAndTheLivelyOneOwnsNowPlaying() {
        MediaSessionEntry Entry(string id, ulong ordinal, MediaPlaybackState playback, bool audible) => new(id, ordinal, playback, audible);
        var arbitration = Arbitrate([
            Entry("c", 9, MediaPlaybackState.Paused, true),
            Entry("a", 2, MediaPlaybackState.Playing, false),
            Entry("b", 5, MediaPlaybackState.Playing, true),
            Entry("d", 1, MediaPlaybackState.None, true)
        ]);
        Assert.Equal([3, 1, 2, 0], arbitration.Order);
        Assert.Equal(2, arbitration.NowPlaying);

        var tie = Arbitrate([
            Entry("a", 2, MediaPlaybackState.Paused, true),
            Entry("b", 5, MediaPlaybackState.Paused, true)
        ]);
        Assert.Equal(1, tie.NowPlaying);
        Assert.Null(Arbitrate([Entry("a", 1, MediaPlaybackState.None, true)]).NowPlaying);
        Assert.Equal(new DuplicateMediaSession("a"), Assert.Throws<Rejected>(() => Arbitrate([
            Entry("a", 1, MediaPlaybackState.Paused, true), Entry("a", 2, MediaPlaybackState.Paused, true)
        ])).Rejection);
    }

    [Fact]
    public void TheQueriesAnswerWithoutAnAppAndRefuseMoreSessionsThanTheStoreOrders() {
        var answers = new StandaloneAnswers();
        var decision = answers.Query(new MediaSessionReport(Report(3),
            Fresh with { LastSequence = 2, Ordinal = 4, IsDismissed = true, PreviousPlayback = MediaPlaybackState.Paused }, 3, 6));
        Assert.Equal(new MediaSessionEventDecision(true, 0, MediaSessionDisposition.Publish, true, 4, 6, true), decision);
        var sessions = Enumerable.Range(0, MediaSessionOrder.MaximumSessions + 1)
            .Select(index => new MediaSessionEntry($"tab:{index}", (ulong)index, MediaPlaybackState.Paused, false)).ToArray();
        Assert.Equal(new MediaSessionLimitReached(MediaSessionOrder.MaximumSessions),
            Assert.Throws<Rejected>(() => answers.Query(new MediaSessionOrder(sessions))).Rejection);
        Assert.Equal(new InvalidMediaSessionCount(-1),
            Assert.Throws<Rejected>(() => answers.Query(new MediaSessionReport(Report(1), Fresh, -1, 0))).Rejection);
    }
}
