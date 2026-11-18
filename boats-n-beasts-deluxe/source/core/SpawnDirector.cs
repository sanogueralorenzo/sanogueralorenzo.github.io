namespace BoatsNBeasts.Core;

public sealed class SpawnDirector
{
    public const float BossArrivalSeconds = 8 * 60;
    public const int BossEscortCount = 6;
    float credits = 1;
    static readonly (float Seconds, float Count, float Income)[] Stages =
    [
        (0, 3, .34f), (45, 6, .48f), (110, 10, .76f),
        (190, 15, 1.1f), (300, 22, 1.65f), (480, 30, 2.15f)
    ];

    public EnemyKind Kind(float seconds, float roll)
    {
        float puffer = .74f * Math.Clamp((seconds - 24) / 55, 0, 1);
        float serpent = .68f * Math.Clamp((seconds - 75) / 65, 0, 1);
        float ray = .54f * Math.Clamp((seconds - 135) / 75, 0, 1);
        float choice = roll * (1 + puffer + serpent + ray);
        if (choice < 1) return EnemyKind.Crab;
        if (choice < 1 + puffer) return EnemyKind.Puffer;
        return choice < 1 + puffer + serpent ? EnemyKind.Serpent : EnemyKind.Ray;
    }

    public int Tick(float dt, float seconds, int count, bool boss)
    {
        var (target, income) = At(seconds);
        float swell = .88f + .12f * MathF.Sin(seconds * MathF.Tau / 46);
        credits = Math.Min(1, credits + dt * income * swell * (boss ? .55f : 1));
        if (credits < 1 || count >= (boss ? BossEscortCount : (int)target)) return 0;
        credits = 0;
        return 1;
    }

    static (float Count, float Income) At(float seconds)
    {
        for (int i = 1; i < Stages.Length; i++)
        {
            var a = Stages[i - 1];
            var b = Stages[i];
            if (seconds > b.Seconds) continue;
            float t = Math.Clamp((seconds - a.Seconds) / (b.Seconds - a.Seconds), 0, 1);
            return (a.Count + (b.Count - a.Count) * t, a.Income + (b.Income - a.Income) * t);
        }
        return (Stages[^1].Count, Stages[^1].Income);
    }
}
