using CrestCore.Application;

namespace CrestCore.Contracts;

/// An engine listed the sites that keep data in the profile the core asked
/// about: `Read` says it listed all of them.
public sealed record SiteDataRead(Guid ReadingId, IReadOnlyList<StoredSite> Sites, bool Read) : EngineEvent {
    #region Actions - Routing

    /// One engine answered its part of a reading; an answer from another
    /// engine, or to a reading nobody waits on, changes nothing.
    internal override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        var readings = app.SiteDataReads;
        if (!readings.ByReading.TryGetValue(ReadingId, out var reading) || !ReferenceEquals(reading.Waiting[ReadingId], engine)) return;
        readings.ByReading.Remove(ReadingId);
        reading.Waiting.Remove(ReadingId);
        reading.Complete &= Read;
        SiteDataReads.Add(reading, Sites);
        if (reading.Waiting.Count == 0) SiteDataReads.Finish(reading, app.Device, changes);
    }

    #endregion
}
