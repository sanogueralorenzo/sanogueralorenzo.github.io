namespace BoatsNBeasts.Core;

public enum DailyObjective { Salvage, Chain, Hull }

public readonly record struct DailyChallenge(DateOnly Day, uint Seed, BoatKind Boat, DailyObjective Objective)
{
    public const int Reward = 5;
    public const int ChainTarget = 12;
    public const float HullTarget = .65f;

    public static DailyChallenge Today => For(DateOnly.FromDateTime(DateTime.UtcNow));

    public static DailyChallenge For(DateOnly day)
    {
        uint seed = SeedRandom.Hash(0x62656173u, day.DayNumber, 0);
        int boat = day.DayNumber % BoatSpec.All.Length;
        int objective = (day.DayNumber / BoatSpec.All.Length + boat) % 3;
        return new(day, Math.Max(seed, 1), (BoatKind)boat, (DailyObjective)objective);
    }

    public string Name => Objective switch
    {
        DailyObjective.Salvage => "Full manifest",
        DailyObjective.Chain => "Rolling thunder",
        _ => "Sound hull"
    };

    public string Rule => Objective switch
    {
        DailyObjective.Salvage => "Deliver wreck salvage and defeat Crownclaw.",
        DailyObjective.Chain => $"Land a {ChainTarget}-beast chain and defeat Crownclaw.",
        _ => $"Defeat Crownclaw with at least {HullTarget:P0} hull."
    };

    public string Progress(Voyage run) => Objective switch
    {
        DailyObjective.Salvage => run.Salvage.Delivered ? "Salvage delivered" : "Deliver wreck salvage",
        DailyObjective.Chain => $"Best chain {run.LongestChain}/{ChainTarget}",
        _ => $"Hull {Math.Max(0, run.Health) / run.MaxHealth:P0} · Need {HullTarget:P0}"
    };

    public bool ObjectiveMet(Voyage run) => Objective switch
    {
        DailyObjective.Salvage => run.Salvage.Delivered,
        DailyObjective.Chain => run.LongestChain >= ChainTarget,
        _ => run.Health >= HullTarget * run.MaxHealth
    };

    public bool Qualifies(Voyage run) => run.BossSlain && run.Boat == Boat && run.World.Seed == Seed &&
        run.Charter == Charter.Coastguard && ObjectiveMet(run);
}
