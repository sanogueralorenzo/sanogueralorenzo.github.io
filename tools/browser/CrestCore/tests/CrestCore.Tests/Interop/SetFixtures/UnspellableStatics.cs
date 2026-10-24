using CrestCore.Contracts;

namespace CrestCore.Tests.Unspellable;

/// Swift cannot spell a GUID as a literal.
public sealed record Stamped(string Label) : Change {
    public static Guid Nobody { get; } = Guid.Empty;
}

/// A value Swift receives as a literal cannot change.
public sealed record Settable(string Label) : Change {
    public static Settable Current { get; set; } = new("");
}
