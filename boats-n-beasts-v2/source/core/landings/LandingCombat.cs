using System.Numerics;

namespace BoatsNBeasts.Core;

public enum YardBeast { Scrapper, Slinger, Porter, Skater, Guardian }
public enum AttackShape { Disc, Ring, Lane, Fan }

public sealed class YardBeastState(Vector2 position, YardBeast kind, int health)
{
    public Vector2 Position = position, Heading = -Vector2.UnitY, RushTo;
    public readonly YardBeast Kind = kind;
    public readonly int Maximum = health;
    public int Health = health, Pattern;
    public float Wait = .9f, Stagger, Hit, Rush;
    public bool Enraged;
    public Vector2 Waypoint;
    public float PathUpdate;
}

public sealed class YardAttack(YardBeastState source, AttackShape shape, Vector2 origin, Vector2 target, float radius,
    float inner, float lead, float active, bool rush = false)
{
    public readonly YardBeastState Source = source;
    public readonly AttackShape Shape = shape;
    public readonly Vector2 Origin = origin, Target = target;
    public readonly float Radius = radius, Inner = inner, Lead = lead, Active = active;
    public readonly bool Rush = rush;
    public float Age;
    public bool Fired, Hurt;
    public float Windup => Math.Clamp(Age / Lead, 0, 1);
    public bool Contains(Vector2 p)
    {
        float range = Vector2.Distance(p, Origin);
        return Shape switch
        {
            AttackShape.Ring => range >= Inner && range <= Radius,
            AttackShape.Disc => range <= Radius,
            AttackShape.Lane => SegmentDistance(p, Origin, Target) <= Radius,
            _ => range <= Radius && (range < .18f || Vector2.Dot((p - Origin) / range, Vector2.Normalize(Target - Origin)) >= Inner)
        };
    }
    static float SegmentDistance(Vector2 p, Vector2 a, Vector2 b)
    {
        var axis = b - a;
        float fraction = Math.Clamp(Vector2.Dot(p - a, axis) / Math.Max(.001f, axis.LengthSquared()), 0, 1);
        return Vector2.Distance(p, a + axis * fraction);
    }
}

public sealed partial class LandingYard
{
    void SpawnWatch(Vector2 center, bool gate)
    {
        int count = gate ? 2 + Math.Min(District / 2, 2) : 2 + Math.Min(District % 3, 1);
        if (Order.Tier >= 5 && District > 0) count++;
        GuardCount = count;
        for (int i = 0; i < count; i++)
        {
            float a = (i + .3f) * MathF.Tau / count;
            var local = new Vector2(MathF.Cos(a) * (gate ? 2.8f : 1.78f), MathF.Sin(a) * (gate ? 1.9f : 1.25f));
            var kind = (YardBeast)((rand.Next(4) + (int)Region.Climate + i) % 4);
            int hp = kind == YardBeast.Porter ? 34 : kind == YardBeast.Slinger ? 20 : 25;
            Foes.Add(new(Walkable(center + local), kind, hp) { Wait = .8f + i * .24f });
        }
    }
    void BeastTurn(YardBeastState beast, float dt)
    {
        beast.Hit = Decay(beast.Hit, dt);
        if (beast.Stagger > 0) { beast.Stagger = Decay(beast.Stagger, dt); return; }
        if (beast.Rush > 0)
        {
            beast.Rush = Decay(beast.Rush, dt);
            beast.Position = Walkable(Vector2.Lerp(beast.Position, beast.RushTo, Math.Min(1, dt * 12)));
            return;
        }
        var to = Player - beast.Position;
        bool boss = beast.Kind == YardBeast.Guardian;
        if (boss && !beast.Enraged && beast.Health <= beast.Maximum * .48f)
        {
            beast.Enraged = true; beast.Wait = .6f; GuardPins[0] = GuardPins[1] = true;
            Say(ChargeHarness ? "The harness has chained itself to two rivets. Stand behind each brass pin, dodge the rush, then cut the hot metal." : "Two fittings lock the shell. Hook the west one with K, then cut the east one with J.");
        }
        float clearance = boss ? 1.06f : .48f;
        if (to.LengthSquared() < clearance * clearance) Player = Walkable(beast.Position + Unit(to) * clearance);
        if (Attacks.Any(a => a.Source == beast && !a.Fired)) return;
        beast.Heading = Unit(Player - beast.Position);
        if (beast.Wait > 0) { beast.Wait = Decay(beast.Wait, dt); return; }
        float reach = beast.Kind switch { YardBeast.Scrapper or YardBeast.Porter => 1.28f, YardBeast.Slinger => 4.6f, YardBeast.Guardian when Harness && ChargeHarness => 6.1f, _ => 4.2f };
        if (to.Length() > reach)
        {
            float speed = beast.Kind switch { YardBeast.Porter => 1.22f, YardBeast.Skater => 2.25f, _ => 1.75f };
            beast.PathUpdate -= dt;
            if (beast.PathUpdate <= 0)
            { beast.Waypoint = Plan.Waypoint(beast.Position, Player); beast.PathUpdate = .34f; }
            var toward = beast.Waypoint - beast.Position;
            if (toward.LengthSquared() > .025f) beast.Position = Walkable(beast.Position + Unit(toward) * (dt * speed));
            return;
        }
        beast.Pattern++;
        if (boss) GuardianAttack(beast);
        else
        {
            switch (beast.Kind)
            {
                case YardBeast.Scrapper: Fan(beast, 1.55f, .12f, .74f); break;
                case YardBeast.Slinger: Disc(beast, Player, 1.01f, .95f); break;
                case YardBeast.Porter: Ring(beast, beast.Position, .36f, 1.87f, 1.03f); break;
                case YardBeast.Skater: Lane(beast, beast.Position, beast.Position + beast.Heading * 3.9f, .44f, .85f, true); break;
            }
            beast.Wait = 1.00f + (beast.Kind == YardBeast.Porter ? .6f : .25f);
        }
    }
    void GuardianAttack(YardBeastState b)
    {
        var h = b.Heading;
        var side = new Vector2(-h.Y, h.X);
        var p = b.Position;
        float lead = b.Enraged ? .80f : 1.07f;
        bool second = b.Pattern % 2 == 0;
        if (Harness && ChargeHarness)
        {
            Lane(b, p, p + h * 6.4f, .82f, .98f, true); b.Wait = 1.18f; return;
        }
        if (breed != GuardianForm.Regional)
        {
            switch (breed)
            {
                case GuardianForm.Cat:
                    Lane(b, p, p + h * (3.6f + flourish * .45f), .51f, lead, true);
                    if (second) Fan(b, 2.25f, .14f, lead + .47f); break;
                case GuardianForm.Bird:
                    Disc(b, Player, 1.12f, lead);
                    if (second || b.Enraged) Lane(b, p, Player + side * (.6f + flourish * .24f), .40f, lead + .38f, true); break;
                case GuardianForm.Serpent:
                    Fan(b, 2.56f, .15f, lead); if (second) Ring(b, p, .91f, 2.5f, lead + .46f); break;
                case GuardianForm.Insect:
                    Lane(b, p, p + h * 4.7f, .4f, lead, true); if (second) Disc(b, Player + side * .87f, 1.02f, lead + .36f); break;
                case GuardianForm.Shell:
                    Disc(b, p, 2.15f + .13f * flourish, lead); if (second) Disc(b, Player, 1.02f, lead + .52f); break;
                case GuardianForm.Weaver:
                    Lane(b, Player - side * 2.75f, Player + side * 2.75f, .39f, lead);
                    Lane(b, Player - h * 2.3f, Player + h * 2.3f, .36f, lead + .40f); break;
                case GuardianForm.Drake:
                    Fan(b, 3.0f, .62f, lead); Disc(b, Player + h * .76f, 1, lead + .58f); break;
                default:
                    Disc(b, Player - side * .83f, 1.11f, lead); Disc(b, Player + side * .83f, 1.1f, lead + .53f); break;
            }
            if (b.Enraged && flourish == 1) Ring(b, p, 2, 3.05f, lead + .88f);
            b.Wait = b.Enraged ? .83f : 1.28f; return;
        }
        if (Order.Boss switch { "Stamp Beetle" or "Freezer Dog" or "Cradle Hornet" or "Ward Lamprey" or "Tally Jack" or "The Brass Balance" or "The Plumb Serpent" => true, _ => false })
        {
            switch (Order.Boss)
            {
                case "Stamp Beetle": Disc(b, Player, 1.43f, lead); if (second || b.Enraged) Disc(b, Player + h * 1.6f, 1.20f, lead + .45f); break;
                case "Freezer Dog": Lane(b, p, p + h * 4.9f, .52f, lead, true); if (second) Disc(b, p, 1.48f, lead + .40f); break;
                case "Cradle Hornet": Lane(b, p, p + h * 5.2f, .40f, lead, true); if (second || b.Enraged) Lane(b, p + side * .78f, p + h * 5.2f + side * .78f, .37f, lead + .34f); break;
                case "Ward Lamprey": Fan(b, 2.43f, .42f, lead); if (second || b.Enraged) Ring(b, p, .64f, 2.10f, lead + .49f); break;
                case "Tally Jack": Fan(b, 2.66f, .22f, lead); Lane(b, p - side * 1.5f, p + side * 1.5f, .48f, lead + .58f); break;
                case "The Brass Balance": Disc(b, Player + side * .81f, 1.14f, lead); Disc(b, Player - side * .81f, 1.14f, lead + .45f); break;
                default: Lane(b, p, p + h * 4.6f, .59f, lead, true); Ring(b, Player, 1.09f, 2.4f, lead + .54f); break;
            }
            b.Wait = b.Enraged ? .83f : 1.21f; return;
        }
        switch (Region.Climate)
        {
            case IslandClimate.Kiln:
                if (second) Fan(b, 2.85f, -.14f, lead);
                else Lane(b, p, p + h * 5.2f, .75f, lead, true);
                if (b.Enraged) Disc(b, Player + side * 1.0f, .95f, lead + .52f);
                break;
            case IslandClimate.Delta:
                if (second) Lane(b, p, p + h * 5.0f, .44f, lead);
                else { Disc(b, Player, 1.1f, lead); Disc(b, Player - h * 1.6f, .9f, lead + .42f); }
                if (b.Enraged) Disc(b, Player + h * 1.3f, 1, lead + .78f);
                break;
            case IslandClimate.Orchard:
                Ring(b, p, second ? 1.1f : 2.35f, second ? 2.5f : 4.2f, lead);
                if (b.Enraged || second) Disc(b, Player + side * .7f, 1.1f, lead + .5f);
                break;
            case IslandClimate.Shelf:
                Disc(b, Player, 1.4f, lead); if (second) Lane(b, p, Player + h * .7f, .70f, lead + .24f, true);
                if (b.Enraged) Disc(b, p, 1.55f, lead + .70f);
                break;
            case IslandClimate.Loom:
                Lane(b, Player - side * 2.8f, Player + side * 2.8f, .43f, lead);
                Lane(b, Player - h * 2.7f, Player + h * 2.7f, .39f, lead + .40f);
                if (b.Enraged) Ring(b, p, 1.6f, 2.8f, lead + .68f);
                break;
            case IslandClimate.Reef:
                Ring(b, p, 1.65f, 3.35f, lead); Disc(b, p, 1.55f, lead + .56f);
                if (b.Enraged) Ring(b, p, 2.95f, 4.5f, lead + .94f);
                break;
            case IslandClimate.Court:
                Lane(b, p, p + h * 4.6f, .60f, lead, true);
                if (second || b.Enraged) Fan(b, 2.6f, .18f, lead + .47f);
                break;
            case IslandClimate.Stars:
                var diagonal = Unit(h + side);
                Lane(b, Player - diagonal * 3.1f, Player + diagonal * 3.1f, .49f, lead);
                if (second || b.Enraged) { diagonal = Unit(h - side); Lane(b, Player - diagonal * 3.1f, Player + diagonal * 3.1f, .55f, lead + .49f); }
                break;
        }
        b.Wait = b.Enraged ? .86f : 1.34f;
    }
    void Disc(YardBeastState b, Vector2 p, float r, float lead) => Attacks.Add(new(b, AttackShape.Disc, p, p, r, 0, lead, .25f));
    void Ring(YardBeastState b, Vector2 p, float inner, float outer, float lead) => Attacks.Add(new(b, AttackShape.Ring, p, p, outer, inner, lead, .26f));
    void Fan(YardBeastState b, float r, float cosine, float lead) => Attacks.Add(new(b, AttackShape.Fan, b.Position, b.Position + b.Heading, r, cosine, lead, .22f));
    void Lane(YardBeastState b, Vector2 from, Vector2 to, float radius, float lead, bool rush = false) => Attacks.Add(new(b, AttackShape.Lane, from, to, radius, 0, lead, .27f, rush));
}
