namespace BoatsNBeasts.Core;

public enum Charter { Coastguard, Salvager, Stormchaser }

public sealed record CharterRules(string Name, string Description, int Price, float HullFactor, float EnemySpeed, float EnemyHull, float SilverFactor)
{
    public static readonly CharterRules[] All =
    [
        new("Coastguard", "Standard hull, beasts, and rewards.", 0, 1, 1, 1, 1),
        new("Salvager", "Beach chests grant double XP and 2 silver. Salvage restores 45 hull and pays 5 silver. Your boat has 20% less hull.", 8, .8f, 1, 1, 1),
        new("Stormchaser", "Earn 50% more silver. Beasts swim 20% faster and have 25% more health.", 15, 1, 1.2f, 1.25f, 1.5f)
    ];

    public static CharterRules For(Charter charter) => All[(int)charter];
}
