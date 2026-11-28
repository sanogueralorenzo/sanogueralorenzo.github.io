namespace BoatsNBeasts.Core;

public enum Passage { LanternSound, BellwetherQuay }
public enum CrewPromise { Unspoken, RememberTheMissing, WelcomeHome }
public enum BellDedication { Unrung, RollCall, Children }

public sealed record HarborLedger
{
    public int Silver { get; init; }
    public int Stores { get; init; }
    public bool HasTongue { get; init; }
    public bool BellReleased { get; init; }
    public CrewPromise Promise { get; init; }
    public BellDedication Dedication { get; init; }
    public bool Dedicated => Dedication != BellDedication.Unrung;
    public int AtSea { get; init; }
    public int StoreCost => Stores == 0 ? 6 : 14;
    public HarborLedger Land(Passage passage, bool won, int earned) => this with
    {
        Silver = checked(Silver + Math.Max(0, earned)),
        AtSea = 0,
        HasTongue = HasTongue || won && passage == Passage.LanternSound,
        BellReleased = BellReleased || won && HasTongue && passage == Passage.BellwetherQuay
    };
    public HarborLedger FitGalley() => Stores >= 2 || Silver < StoreCost
        ? this : this with { Silver = Silver - StoreCost, Stores = Stores + 1 };
}
