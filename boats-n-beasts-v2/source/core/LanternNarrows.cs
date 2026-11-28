using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class LanternPassage
{
    public readonly record struct Drifter(Vector2 Mooring, float Phase, bool Coin);
    public IReadOnlyList<Drifter> Drift => drift;
    public HashSet<int> Cleared { get; } = [];
    public static readonly Vector2 FightGround = new(0, -5380), Tender = new(-80, -3450);
    public int Repairs { get; private set; }
    public bool Rescue { get; private set; }
    public int Hands { get; private set; }
    public float RouteTime { get; private set; }
    public Vector2 HookTo { get; private set; }
    public bool TowAboard => Rescue && Hands > 0 && Leg is PassageLeg.Work or PassageLeg.Delivery;
    public bool TowLoose { get; private set; }
    public Vector2 Tow { get; private set; }
    public Vector2 WorkPosition => Stops()[Hands];
    public bool GuardLive => Leg == PassageLeg.Work && !Rescue && !guardBroken;
    public Vector2 Guard => WorkPosition + new Vector2(-65 * Bearing, 42);
    public float GuardFuse { get; private set; }
    public Vector2 GuardAim { get; private set; }
    float guardReload;
    bool guardBroken;
    public Vector2 Tongue => Beast + new Vector2(44, 44);
    public Vector2 TaskPosition => TowLoose ? Tow : Leg switch
    {
        PassageLeg.Work => Stops()[Hands],
        PassageLeg.Delivery or PassageLeg.Homeward => Tender,
        PassageLeg.Hunt => FightGround + new Vector2(0, 330),
        PassageLeg.Wreck => Tongue,
        _ => Hull
    };
    public string TaskName => TowLoose ? "Drifting lifeboat" : Leg switch
    {
        PassageLeg.Work when Rescue => Hands == 0 ? "First castaway" : "Second castaway",
        PassageLeg.Work => Hands == 0 ? "Powder lighter" : "Magazine raft",
        PassageLeg.Delivery => "Hushlight tender",
        PassageLeg.Hunt => "The outer roadstead",
        PassageLeg.Wreck => "Bronze tongue",
        PassageLeg.Homeward => "Hushlight tender",
        _ => ""
    };
    readonly List<Drifter> drift = [];
    Vector2[] rescueStops = [], powderStops = [];
    Vector2[] Stops() => Rescue ? rescueStops : powderStops;

    void MapNarrows(ref SeedRandom random)
    {
        rescueStops = [new(-655 * Bearing, -1860), new(-475 * Bearing, -2780)];
        powderStops = [new(660 * Bearing, -2000), new(470 * Bearing, -2830)];
        for (int course = -1; course <= 1; course++)
            for (int j = 0; j < 9; j++)
            {
                float x = course * 510 + random.Range(-120, 120);
                float y = -710 - j * 485 + random.Range(-125, 125);
                var mooring = new Vector2(x, y);
                if (Coast.Any(shore => OceanWorld.Overlap(shore, mooring, 96, out _, out _))) continue;
                drift.Add(new(mooring, random.Range(0, 6.28f), j % 4 == 0));
            }
        for (int i = 0; i < 2; i++)
        {
            drift.Add(new(powderStops[i] + new Vector2(18, -5), random.Range(0, 6.28f), false));
            drift.Add(new(rescueStops[i] + new Vector2(100, -80), random.Range(0, 6.28f), false));
        }
    }

    public Vector2 DriftPosition(Drifter d) => d.Mooring + new Vector2(
        MathF.Sin(RouteTime * .38f + d.Phase) * (d.Coin ? 19 : 80), MathF.Cos(RouteTime * .62f + d.Phase) * 18);

    void CheckFlotsam(bool fire)
    {
        if (Battle) return;
        int target = -1;
        float closest = 380;
        for (int i = 0; i < drift.Count; i++)
        {
            if (Cleared.Contains(i)) continue;
            var item = drift[i];
            var d = Vector2.Distance(DriftPosition(item), Hull);
            if (d < (item.Coin ? 61 : 81))
            {
                Cleared.Add(i);
                if (item.Coin) Silver += 2;
                else Hurt(17);
            }
            else if (!item.Coin && TowAboard && !TowLoose && Vector2.Distance(DriftPosition(item), Tow) < 71)
            {
                Cleared.Add(i);
                TowLoose = true;
                Speak("Lio    Painter's snapped! Bring me within line's reach of the lifeboat.", 4);
            }
            else if (fire && !item.Coin && d < closest && SideOn(DriftPosition(item)))
            {
                closest = d;
                target = i;
            }
        }
        if (target < 0 || gunReload > 0) return;
        gunReload = 1.12f;
        GunFrom = Hull;
        GunTo = DriftPosition(drift[target]);
        GunFlash = .26f;
        Cleared.Add(target);
    }

    bool SideOn(Vector2 target) => Math.Abs(Vector2.Dot(Bow, OceanWorld.Unit(target - Hull))) < .70f;

    void HandleWatch(float dt, bool fire)
    {
        if (TowAboard && !TowLoose)
        {
            var direction = OceanWorld.Unit(Hull - Tow, Bow);
            float length = Vector2.Distance(Hull, Tow);
            float crossTide = MathF.Sin(RouteTime * .95f + Hull.Y * .003f) * 77;
            Tow = OpenWater(Tow + (direction * Math.Max(0, length - 100) * 3 + new Vector2(crossTide, 0)) * dt);
        }
        if (!GuardLive || Vector2.Distance(Hull, Guard) > 550) return;
        guardReload -= dt;
        if (GuardFuse > 0)
        {
            GuardFuse -= dt;
            if (GuardFuse <= 0 && Vector2.Distance(Hull, GuardAim) < 115) Hurt(18);
        }
        if (guardReload <= 0)
        {
            GuardAim = Hull + Velocity * .25f;
            GuardFuse = 1.45f;
            guardReload = 3.4f;
        }
        if (!fire || gunReload > 0 || !SideOn(Guard) || Vector2.Distance(Hull, Guard) > 445) return;
        GunFrom = Hull;
        GunTo = Guard;
        GunFlash = .26f;
        gunReload = .83f;
        guardBroken = true;
        GuardFuse = 0;
        Speak("Vara    I've cut the spring on that old deck gun. Lio can take the powder!", 3.2f);
    }

    void Navigate(bool hook)
    {
        if (Leg == PassageLeg.Salvage)
        {
            bool rescue = Vector2.Distance(Hull, RepairBuoy) < 87;
            if (!rescue && Vector2.Distance(Hull, PowderBuoy) >= 87) return;
            Rescue = rescue;
            Leg = PassageLeg.Work;
            HookCooldown = 0;
            Speak(rescue ? "Vara    Two hands missing in the kelp. Get Lio close enough to throw a line." :
                "Vara    Deck guns on springs. Turn us side-on to knock them off the lighters.", 6);
            return;
        }
        float distance = Vector2.Distance(Hull, TaskPosition);
        if (TowLoose)
        {
            if (hook && distance < 265)
            {
                TowLoose = false;
                HookTo = Tow;
                HookFlash = .7f;
                Speak("Lio    Back in tow. Keep her clear of the red floats!", 3);
            }
            return;
        }
        if (Leg == PassageLeg.Work && !GuardLive && hook && distance <= (Rescue ? 270 : 205))
        {
            HookTo = TaskPosition;
            HookFlash = .7f;
            if (Rescue && Hands == 0) Tow = TaskPosition;
            guardBroken = false;
            guardReload = .75f;
            Hands++;
            Silver += 2;
            if (Rescue) Repairs++;
            else powder += 2;
            if (Hands == 2) Leg = PassageLeg.Delivery;
            Speak(Rescue ? "Lio    Alive! She brought her caulking bag. E for a hull patch." :
                "Vara    Powder aboard. That'll give each broadside more bite.", 4);
        }
        else if (Leg == PassageLeg.Delivery && distance < 115)
        {
            Silver += 2;
            Leg = PassageLeg.Hunt;
            Speak(Rescue ? "Skiffmaster    It took the toll bell north. Follow the floating red paint." :
                "Skiffmaster    That tongue left a bronze scrape on every rock north of here.", 6);
        }
        else if (Leg == PassageLeg.Hunt && distance < 130)
        {
            Leg = PassageLeg.Keelwidow;
            Beast = FightGround + new Vector2(210 * Bearing, -105);
            BeastHealth = BeastMaximum = 165;
            attackCount = 0;
            HookCooldown = 0;
            SetMove(HaulerMove.Stalking, 2.7f);
            Speak("Vara    That's no shipwreck. Look at the legs under it!", 4);
        }
        else if (Leg == PassageLeg.Wreck && hook && distance < 215)
        {
            HookTo = Tongue;
            HookFlash = .7f;
            Leg = PassageLeg.Homeward;
            Speak("Lio    Wrapped in felt. Even a wreck couldn't ring it. Let's get this back to the tender.", 6);
        }
        else if (Leg == PassageLeg.Homeward && distance < 115)
        {
            Leg = PassageLeg.Recovered;
            Speak("Skiffmaster    You'll want the bellfounder to hear this one.", 4);
        }
    }
}
