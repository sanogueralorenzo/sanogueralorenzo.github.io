using CrestCore.Contracts;

namespace CrestCore.Tests.Spelled;

/// Held modifiers, as a flags enum.
[Flags]
public enum Hold { None = 0, Command = 1, Shift = 8 }

public sealed class Grip {
    public static readonly Grip Firm = new("firm");
    public static readonly Grip Loose = new("loose");
    public static IReadOnlyList<Grip> All { get; } = [Firm, Loose];

    public string Name { get; }

    private Grip(string name) => Name = name;
}

public sealed record Binding(Grip Grip, Hold Modifiers);

/// A set no record names, with a list of records holding a set and flags, and
/// a title that carries its number.
public sealed class Key {
    public static readonly Key Any = new("any", "Any Key", null, []);
    public static readonly Key Second = new("second", "Press Key %lld", 2,
        [new Binding(Grip.Firm, Hold.Command | Hold.Shift), new Binding(Grip.Loose, Hold.None)]);
    public static IReadOnlyList<Key> All { get; } = [Any, Second];

    public string Name { get; }

    [Localized(Argument = nameof(Number))]
    public string Title { get; }

    public int? Number { get; }
    public IReadOnlyList<Binding> Bindings { get; }

    private Key(string name, string title, int? number, IReadOnlyList<Binding> bindings) {
        Name = name;
        Title = title;
        Number = number;
        Bindings = bindings;
    }
}
