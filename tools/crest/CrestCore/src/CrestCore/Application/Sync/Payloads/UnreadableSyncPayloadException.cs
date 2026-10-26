namespace CrestCore.Application;

/// A synced payload or tombstone that no Apple client reads, or that breaks a
/// rule every client checks before it takes a record. A record that carries one
/// is skipped as unreadable, never applied.
internal sealed class UnreadableSyncPayloadException() : Exception("A synced record cannot be read.");
