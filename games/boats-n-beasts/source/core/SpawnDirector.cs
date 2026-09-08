namespace BoatsNBeasts.Core;

// Megabonk-inspired budget/target separation. Values below are original boat-game tuning.
public sealed class SpawnDirector
{
    public float Credits, Clock, EncounterTime;
    public int Target(int tier) => Math.Min(64, 5 + tier * 5);
    public float Income(int tier) => 1.15f + .65f * tier;
    public int Tick(float dt, int tier, int count, bool safe, bool boss = false)
    {
        if (safe) { Credits = Math.Min(Credits, 2); Clock = 0; return 0; }
        EncounterTime += dt;
        // Short lulls let the captain clear a pack and choose a route before the next swell.
        float phase = EncounterTime % 36;
        float pressure = phase > 27 ? .22f : phase < 8 ? .7f : 1.2f;
        int target = boss ? 8 : Target(tier);
        Credits = Math.Min(Credits + dt * Income(tier) * pressure * (boss ? .45f : 1) * (count >= target ? .12f : 1), 10 + tier * 2);
        Clock += dt;
        if (Clock < .65f || count >= target) return 0;
        Clock = 0;
        int amount = Math.Min(Math.Min((int)Credits, 3 + tier / 2), target - count);
        Credits -= amount; return amount;
    }
}
