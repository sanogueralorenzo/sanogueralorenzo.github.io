using System.Numerics;

namespace BoatsNBeasts.Core;

public enum PassageLeg { Escort, Salvage, Work, Delivery, Hunt, Keelwidow, Wreck, Homeward, Recovered, Wrecked }
public enum HaulerMove { Stalking, LiningUp, Charging, Sounding, Throwing, Exposed }

public sealed partial class LanternPassage
{
    public static readonly IReadOnlyList<Place> Coast = Array.AsReadOnly<Place>([
        new("First Light", PlaceKind.Island, new(-790, -385), 230, 2),
        new("Ledge", PlaceKind.Rock, new(805, 416), 84, 35),
        new("Needle", PlaceKind.Island, new(751, -1050), 165, 94),
        new("Knuckle", PlaceKind.Rock, new(-790, -1040), 88, 27),
        new("Split Sand", PlaceKind.Island, new(0, -1470), 195, 37),
        new("Salt Shed", PlaceKind.Island, new(860, -2350), 290, 67),
        new("Carpenter's Rock", PlaceKind.Island, new(-900, -2680), 245, 54),
        new("Buoy Yard", PlaceKind.Island, new(480, -3520), 213, 23),
        new("Black Tooth", PlaceKind.Rock, new(-560, -4170), 105, 54),
        new("Outer Light", PlaceKind.Island, new(790, -4990), 240, 2),
        new("Sister Light", PlaceKind.Rock, new(-860, -4990), 172, 49)
    ]);
    public Vector2 Hull { get; private set; }
    public Vector2 Velocity { get; private set; }
    public Vector2 Bow { get; private set; } = new(0, -1);
    public Vector2 Beast { get; private set; }
    public Vector2 Aim { get; private set; }
    public Vector2 WarningOrigin { get; private set; }
    public Vector2 GunFrom { get; private set; }
    public Vector2 GunTo { get; private set; }
    public float GunFlash { get; private set; }
    public float HookFlash { get; private set; }
    public float ImpactFlash { get; private set; }
    public float WoundFlash { get; private set; }
    public float SurgeLeft { get; private set; }
    public float SurgeCooldown { get; private set; }
    public float HookCooldown { get; private set; }
    public float MoveTime { get; private set; }
    public int HullHealth { get; private set; }
    public int HullMaximum { get; }
    public int BeastHealth { get; private set; }
    public int BeastMaximum { get; private set; }
    public int Silver { get; private set; }
    public PassageLeg Leg { get; private set; }
    public HaulerMove Move { get; private set; }
    public int Bearing { get; }
    public Vector2 RepairBuoy => new(-530 * Bearing, -1090);
    public Vector2 PowderBuoy => new(530 * Bearing, -1090);
    public Vector2 Center => Leg == PassageLeg.Escort ? Vector2.Zero : Leg == PassageLeg.Keelwidow ? FightGround : Hull;
    public string Callout { get; private set; } = "Vara    Hear that tapping? It's coming from inside the tow.";
    public float CalloutLeft { get; private set; } = 4;
    public bool InRange => Vector2.Distance(Hull, Beast) < 645;
    public bool Broadside => Math.Abs(Vector2.Dot(Bow, OceanWorld.Unit(Beast - Hull))) < .61f;
    public float WaveRadius => Move == HaulerMove.Throwing || lastThrow && ImpactFlash > 0 ? 148 : 265;
    public Vector2 Blast { get; private set; }
    bool lastThrow;
    public bool Battle => Leg is PassageLeg.Escort or PassageLeg.Keelwidow;
    public float ChargeWidth => Leg == PassageLeg.Keelwidow ? 153 : 111;
    float gunReload, immunity, moveDuration;
    int attackCount, powder;
    readonly int spiral;

    public LanternPassage(int seed, int stores)
    {
        var random = new SeedRandom((uint)seed);
        Bearing = random.Index(2) == 0 ? -1 : 1;
        spiral = random.Index(2) == 0 ? -1 : 1;
        Hull = new(-204 * Bearing, 150);
        Beast = new(222 * Bearing, -75);
        BeastHealth = BeastMaximum = 48;
        HullHealth = HullMaximum = 100 + 15 * Math.Clamp(stores, 0, 2);
        MapNarrows(ref random);
        SetMove(HaulerMove.Stalking, 3);
    }

    public void Tick(float dt, Vector2 steer, bool fire, bool hook, bool surge, bool patch)
    {
        if (Leg is PassageLeg.Recovered or PassageLeg.Wrecked) return;
        if (patch && Repairs > 0 && HullHealth < HullMaximum)
        {
            Repairs--;
            HullHealth = Math.Min(HullMaximum, HullHealth + 42);
            Speak("Vara    Another seam stitched shut!", 2);
        }
        HookCooldown = Math.Max(0, HookCooldown - dt);
        SurgeCooldown = Math.Max(0, SurgeCooldown - dt);
        SurgeLeft = Math.Max(0, SurgeLeft - dt);
        HookFlash = Math.Max(0, HookFlash - dt);
        ImpactFlash = Math.Max(0, ImpactFlash - dt);
        GunFlash = Math.Max(0, GunFlash - dt);
        WoundFlash = Math.Max(0, WoundFlash - dt);
        CalloutLeft -= dt;
        gunReload -= dt;
        immunity -= dt;
        if (steer.LengthSquared() > .01f)
        {
            steer = Vector2.Normalize(steer);
            float turn = Math.Clamp(MathF.Atan2(Bow.X * steer.Y - Bow.Y * steer.X, Vector2.Dot(Bow, steer)), -4.8f * dt, 4.8f * dt);
            Bow = Vector2.TransformNormal(Bow, Matrix3x2.CreateRotation(turn));
        }
        if (surge && SurgeCooldown <= 0)
        {
            SurgeCooldown = 3.4f;
            SurgeLeft = .52f;
        }
        Vector2 desired = SurgeLeft > 0 ? Bow * 490 : steer * (TowAboard && !TowLoose ? 204 : 247);
        Velocity = Vector2.Lerp(Velocity, desired, 1 - MathF.Exp(-6 * dt));
        Vector2 next = Hull + Velocity * dt;
        Hull = OpenWater(next);
        RouteTime += dt;
        HandleWatch(dt, fire);
        CheckFlotsam(fire);
        if (Leg == PassageLeg.Wrecked) return;
        if (!Battle)
        {
            Navigate(hook);
            return;
        }
        if (hook && HookCooldown <= 0 && Vector2.Distance(Hull, Beast) <= 530)
        {
            HookCooldown = 6;
            HookFlash = .58f;
            HookTo = Beast;
            bool counter = Move is HaulerMove.LiningUp or HaulerMove.Sounding or HaulerMove.Throwing;
            SetMove(HaulerMove.Exposed, counter ? 3 : 1);
            BeastHealth -= counter ? 12 : 3;
            Speak(counter ? "Lio    Iron's fast! Vara, take the seam!" : "Lio    I've caught the rim. Fire now!", 2.2f);
        }
        if (fire && gunReload <= 0 && InRange)
        {
            gunReload = .83f;
            GunFlash = .26f;
            GunFrom = Hull;
            GunTo = Beast;
            bool plated = Leg == PassageLeg.Keelwidow && BeastHealth <= BeastMaximum / 2 && Move != HaulerMove.Exposed;
            BeastHealth -= plated ? (Broadside ? 2 : 1) : (Broadside ? 5 + powder : 2) + (Move == HaulerMove.Exposed ? 4 : 0);
        }
        if (BeastHealth <= 0)
        {
            BeastHealth = 0;
            bool boss = Leg == PassageLeg.Keelwidow;
            Silver += boss ? 12 : 4;
            Leg = boss ? PassageLeg.Wreck : PassageLeg.Salvage;
            HookCooldown = 0;
            Speak(boss ? "Lio    There! The tongue is rolling off the broken keel. Bring me alongside!" : "Lio    Two boats have put up flags. Which watch are we taking?", 6);
            return;
        }
        TickBeast(dt);
    }

    void TickBeast(float dt)
    {
        MoveTime -= dt;
        Vector2 toward = OceanWorld.Unit(Hull - Beast, new(0, 1));
        if (Move == HaulerMove.Stalking)
        {
            var tangent = new Vector2(-toward.Y, toward.X) * spiral;
            Beast += ((Vector2.Distance(Beast, Hull) > 160 ? toward : -.3f * toward) * 79 + tangent * 20) * dt;
            if (MoveTime <= 0)
            {
                attackCount++;
                bool wave = Leg == PassageLeg.Keelwidow && attackCount % 3 == 2;
                bool throwWreck = Leg == PassageLeg.Keelwidow && attackCount % 3 == 0;
                Blast = throwWreck ? Hull + Velocity * .28f : Beast;
                lastThrow = throwWreck;
                Aim = OceanWorld.Unit(Hull + Velocity * .28f - Beast, toward);
                WarningOrigin = Beast;
                SetMove(throwWreck ? HaulerMove.Throwing : wave ? HaulerMove.Sounding : HaulerMove.LiningUp, throwWreck ? 1.68f : wave ? 1.48f : 1.22f);
            }
        }
        else if (Move == HaulerMove.LiningUp && MoveTime <= 0)
            SetMove(HaulerMove.Charging, .72f);
        else if (Move == HaulerMove.Charging)
        {
            Beast += Aim * (670 * dt);

            if (MoveTime <= 0) SetMove(HaulerMove.Exposed, 1.3f);
        }
        else if (Move is HaulerMove.Sounding or HaulerMove.Throwing && MoveTime <= 0)
        {
            ImpactFlash = .42f;
            if (Vector2.Distance(Hull, Blast) <= WaveRadius + 22) Hurt(27);
            SetMove(HaulerMove.Exposed, 1.7f);
        }
        else if (Move == HaulerMove.Exposed && MoveTime <= 0)
            SetMove(HaulerMove.Stalking, Leg == PassageLeg.Keelwidow && BeastHealth < 75 ? 1.1f : 1.9f);
        Beast = Vector2.Clamp(Beast, Center - new Vector2(600, 355), Center + new Vector2(600, 355));
        var offset = Hull - Beast;
        float clearance = ChargeWidth;
        if (offset.LengthSquared() < clearance * clearance)
        {
            if (Move == HaulerMove.Charging) Hurt(Leg == PassageLeg.Keelwidow ? 23 : 15);
            var away = OceanWorld.Unit(offset, -Aim);
            Hull = OpenWater(Beast + away * clearance);
        }
    }

    Vector2 OpenWater(Vector2 next)
    {
        foreach (var shore in Coast)
            if (OceanWorld.Overlap(shore, next, 45, out var normal, out float depth)) next += normal * depth;
        if (Battle) return new(Math.Clamp(next.X, -680, 680), Math.Clamp(next.Y, Center.Y - 420, Center.Y + 420));
        return Vector2.Clamp(next, new(-960, -5830), new(960, 405));
    }

    public float Windup => 1 - Math.Clamp(MoveTime / moveDuration, 0, 1);
    void SetMove(HaulerMove next, float seconds)
    {
        Move = next;
        MoveTime = moveDuration = seconds;
    }
    void Hurt(int amount)
    {
        if (immunity > 0 || SurgeLeft > 0) return;
        HullHealth = Math.Max(0, HullHealth - amount);
        immunity = 1;
        WoundFlash = .45f;
        if (HullHealth == 0) Leg = PassageLeg.Wrecked;
    }
    void Speak(string line, float time)
    {
        Callout = line;
        CalloutLeft = time;
    }
}
