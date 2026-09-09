namespace WizNDragons.Core;

// Time sets population and replenishment; flying farther never accelerates combat.
public sealed class SpawnDirector
{
    public const float BossArrivalSeconds = 22 * 60;
    public const int BossEscortCount = 8;
    public float Credits, Clock;
    static readonly (float Seconds, float Count, float Income)[] Stages =
    [ (0, 3, .18f), (300, 10, .45f), (600, 20, 1.2f),
      (900, 34, 2.4f), (1200, 50, 3.6f), (1500, 64, 4.8f) ];

    static (float Count, float Income) At(float seconds)
    {
        for (int i = 1; i < Stages.Length; i++)
        {
            var a = Stages[i - 1]; var b = Stages[i];
            if (seconds > b.Seconds) continue;
            float t = Math.Clamp((seconds - a.Seconds) / (b.Seconds - a.Seconds), 0, 1);
            return (a.Count + (b.Count - a.Count) * t, a.Income + (b.Income - a.Income) * t);
        }
        return (Stages[^1].Count, Stages[^1].Income);
    }
    public int Target(float seconds) => (int)At(seconds).Count;
    public float Income(float seconds) => At(seconds).Income;
    public EnemyKind Kind(float seconds, float roll)
    {
        // Introduce each new species over two minutes, without replacing half a wave at once.
        float puffer = .8f * Math.Clamp((seconds - 120) / 120, 0, 1);
        float serpent = .65f * Math.Clamp((seconds - 360) / 120, 0, 1);
        float ray = .55f * Math.Clamp((seconds - 600) / 120, 0, 1);
        float choice = roll * (1 + puffer + serpent + ray);
        if (choice < 1) return EnemyKind.Imp;
        if (choice < 1 + puffer) return EnemyKind.Spark;
        return choice < 1 + puffer + serpent ? EnemyKind.Drake : EnemyKind.Wyrm;
    }
    public int Tick(float dt, float seconds, int count, bool boss = false)
    {
        // Smooth minute-long swells leave breathing room. Never bank a burst of enemies.
        float pressure = .75f + .25f * MathF.Sin(seconds * MathF.Tau / 60);
        int target = boss ? BossEscortCount : Target(seconds);
        Credits = Math.Min(Credits + dt * Income(seconds) * pressure * (boss ? .45f : 1), 1);
        Clock += dt;
        if (Clock < .2f || Credits < 1 || count >= target) return 0;
        Clock = 0; Credits -= 1; return 1;
    }
}
