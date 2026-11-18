namespace BoatsNBeasts.Core;

public enum Charter { Coastguard, Salvager, Stormchaser }

public sealed record CharterRules(string Name, string Description, int Price, float HullFactor, float EnemySpeed, float SilverFactor)
{
    public static readonly CharterRules[] All =
    [
        new("Coastguard", "Standard hull, beasts, and rewards.", 0, 1, 1, 1),
        new("Salvager", $"Double chest XP, 2 silver per chest, and 20% less hull. Deliver salvage for 45 hull and 5 silver, plus {Voyage.PremiumSalvageBonus} at the chart’s premium buyer.", 8, .8f, 1, 1),
        new("Stormchaser", "Earn 50% more silver and face 20% faster beasts. Dodge marked lightning or lure beasts into its path.", 15, 1, 1.2f, 1.5f)
    ];

    public static CharterRules For(Charter charter) => All[(int)charter];
}
