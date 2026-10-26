namespace CrestCore.Contracts;

/// Which way a person steps through an ordered list, such as the tabs a
/// window's sidebar shows or the Spaces it may show: toward the start or
/// toward the end, wrapping at both ends or, for a swipe, stopping at them. A
/// direction travels as its index in `All`, so `All` is append-only.
public sealed class AdjacentDirection {
    #region Static Variables

    public static readonly AdjacentDirection Previous = new(name: "previous", step: -1);
    public static readonly AdjacentDirection Next = new(name: "next", step: 1);

    public static IReadOnlyList<AdjacentDirection> All { get; } = [Previous, Next];

    #endregion

    #region Variables

    public string Name { get; }

    /// How far one step moves along the list: back one, or on one.
    public int Step { get; }

    #endregion

    #region Constructors

    private AdjacentDirection(string name, int step) {
        Name = name;
        Step = step;
    }

    #endregion

    #region Actions - Lookup

    public static AdjacentDirection? Named(string? name) => All.FirstOrDefault(direction => direction.Name == name);

    #endregion

    #region Actions - Stepping

    /// The index one step this way from item `index` reaches among `count`
    /// items, wrapping at both ends.
    public int From(int index, int count) {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(count);
        return ((index + Step) % count + count) % count;
    }

    /// The index one step this way reaches from the gap just before item
    /// `gap`, where an item that is not one of the `count` items sits: on to
    /// the item after the gap, or back to the one before it, wrapping.
    public int FromGap(int gap, int count) => From(Step > 0 ? gap - 1 : gap, count);

    /// The index one step this way from item `index` reaches among `count`
    /// items, or null past either end.
    public int? Within(int index, int count) {
        int reached = index + Step;
        return reached >= 0 && reached < count ? reached : null;
    }

    /// The index one step this way reaches from the gap just before item
    /// `gap`, as `FromGap` does, or null past either end.
    public int? WithinFromGap(int gap, int count) => Within(Step > 0 ? gap - 1 : gap, count);

    /// The item a step this way enters a run at: the end nearest the side it
    /// comes from, so its first going on and its last going back.
    public T Entering<T>(IReadOnlyList<T> run) {
        ArgumentNullException.ThrowIfNull(run);
        return Step > 0 ? run[0] : run[^1];
    }

    #endregion
}
