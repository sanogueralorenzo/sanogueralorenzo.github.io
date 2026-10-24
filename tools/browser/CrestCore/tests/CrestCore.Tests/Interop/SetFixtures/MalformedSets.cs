using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Malformed;

/// `Hidden` is missing from `All`, so it has no wire tag.
public sealed class Unlisted {
    public static readonly Unlisted Shown = new("shown");
    public static readonly Unlisted Hidden = new("hidden");
    public static IReadOnlyList<Unlisted> All { get; } = [Shown];

    public string Name { get; }

    private Unlisted(string name) => Name = name;
}

/// A public constructor would let a value exist that no tag names.
public sealed class Constructible {
    public static readonly Constructible Only = new("only");
    public static IReadOnlyList<Constructible> All { get; } = [Only];

    public string Name { get; }

    public Constructible(string name) => Name = name;
}

/// A date is not a value Swift can spell as a literal.
public sealed class Dated {
    public static readonly Dated Only = new("only", DateTimeOffset.UnixEpoch);
    public static IReadOnlyList<Dated> All { get; } = [Only];

    public string Name { get; }
    public DateTimeOffset When { get; }

    private Dated(string name, DateTimeOffset when) {
        Name = name;
        When = when;
    }
}

public sealed record Stamp(Guid Id);

/// A record held as set data is spelled field by field, and a Guid has no
/// literal.
public sealed class Stamped {
    public static readonly Stamped Only = new("only", new Stamp(Guid.Empty));
    public static IReadOnlyList<Stamped> All { get; } = [Only];

    public string Name { get; }
    public Stamp Stamp { get; }

    private Stamped(string name, Stamp stamp) {
        Name = name;
        Stamp = stamp;
    }
}

/// A title whose argument has a value must spell `%lld` for it.
public sealed class Uncounted {
    public static readonly Uncounted Only = new("only", "Tab", 2);
    public static IReadOnlyList<Uncounted> All { get; } = [Only];

    public string Name { get; }

    [Localized(Argument = nameof(Count))]
    public string Title { get; }

    public int? Count { get; }

    private Uncounted(string name, string title, int? count) {
        Name = name;
        Title = title;
        Count = count;
    }
}

public sealed record SendUnlisted(Unlisted Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

public sealed record SendConstructible(Constructible Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

public sealed record SendDated(Dated Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

public sealed record SendStamped(Stamped Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

public sealed record SendUncounted(Uncounted Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}
