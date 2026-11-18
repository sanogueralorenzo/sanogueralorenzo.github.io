namespace BoatsNBeasts.Core;

public enum Charter { Coastguard, Salvager, Stormchaser }

public sealed record CharterRules(string Name, string Description, int Price, float HullFactor, float EnemySpeed, float EnemyHull, float SilverFactor)
{
    public static readonly CharterRules[] All =
    [
        new("Coastguard", "A balanced hunt through the three beacons.", 0, 1, 1, 1, 1),
        new("Salvager", "Get double XP and 2 silver from beach chests, and extra repairs and silver from salvage. Your hull is 20% lighter.", 8, .8f, 1, 1, 1),
        new("Stormchaser", "Beasts swim 20% faster and have 25% more hull. Earn 50% more silver.", 15, 1, 1.2f, 1.25f, 1.5f)
    ];

    public static CharterRules For(Charter charter) => All[(int)charter];
}
