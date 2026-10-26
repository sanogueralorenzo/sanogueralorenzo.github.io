namespace CrestCore.Contracts;

/// A Space's content-blocking policy and record retention.
public sealed record BrowsingPreferences(ContentBlockingPolicy ContentBlocking, DataRetentionPreferences DataRetention);
