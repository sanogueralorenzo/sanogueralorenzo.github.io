using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class FleetCommand
{
    public FleetStrike Signature => Country.Climate switch
    {
        SeaClimate.Cinder or SeaClimate.Pitch => FleetStrike.Mortar,
        SeaClimate.Delta or SeaClimate.Wax => FleetStrike.Shear,
        SeaClimate.Loom or SeaClimate.Salt => FleetStrike.Nets,
        SeaClimate.Choir or SeaClimate.Drum => FleetStrike.Echo,
        SeaClimate.Court or SeaClimate.Sleep => FleetStrike.Charge,
        SeaClimate.Shelf or SeaClimate.Tin => FleetStrike.Ice,
        SeaClimate.Orchard or SeaClimate.Bottle => FleetStrike.Swarm,
        _ => FleetStrike.Squall
    };
    public string FirstDevice => Signature switch
    {
        FleetStrike.Mortar => "Fire-basket crane",
        FleetStrike.Shear => "Crosscurrent vanes",
        FleetStrike.Nets => "Hauling winch",
        FleetStrike.Echo => "Sounding plate",
        FleetStrike.Charge => "Ram tackle",
        FleetStrike.Ice => "Ice saw",
        FleetStrike.Swarm => "Feed horn",
        _ => "Storm glass"
    };
    public string SecondDevice => Signature switch
    {
        FleetStrike.Mortar => "Shell tender",
        FleetStrike.Shear => "Scissor boom",
        FleetStrike.Nets => "Net magazine",
        FleetStrike.Echo => "Answering drum",
        FleetStrike.Charge => "Steering chains",
        FleetStrike.Ice => "Floe anchor",
        FleetStrike.Swarm => "Lantern rack",
        _ => "Lightning rod"
    };
    void Threats(float dt)
    {
        Breach = Math.Max(0, Breach - dt); nextThreat -= dt; nextBeast -= dt;
        if (nextThreat <= 0)
        {
            Strike();
            nextThreat = (Field == FleetField.Captain ? 4.1f : 5.1f) + (Breach > 0 ? 1.65f : 0) - Math.Min(.6f, Order.Tier * .04f);
        }
        if (nextBeast <= 0 && Field != FleetField.Refuge)
        {
            nextBeast = Field == FleetField.Captain ? 12.3f : 15.6f;
            if (Ship.Enemies.Count < 3 && !(Breach > 0 && Field == FleetField.Passage))
            {
                var spot = Water(Ship.Position + heading * (random.Range(330, 480)) + side * random.Range(-290, 290), 55);
                var foe = Ship.DropPatrol(Signature is FleetStrike.Shear or FleetStrike.Swarm ? EnemyKind.Ray : EnemyKind.Serpent, spot, .89f + Order.Tier * .014f, false);
                if (foe != null) foe.Role = salvos % 3 == 0 ? PatrolRole.Mortar : PatrolRole.Flanker;
            }
        }
        foreach (var lane in Lanes)
        {
            if (!lane.Fired)
            {
                lane.Warning -= dt; if (lane.Warning > 0) continue;
                lane.Fired = true; lane.Live = lane.Strike switch { FleetStrike.Nets or FleetStrike.Ice => 2.8f, FleetStrike.Echo => 1.8f, FleetStrike.Swarm => 1.5f, _ => .7f };
                Ship.Events.Add(new("explosion", lane.To, lane.Width * .70f));
            }
            lane.Live -= dt;
            float power = Field == FleetField.Captain ? 17 + Math.Min(7, Order.Tier) : 12 + Math.Min(6, Order.Tier / 2);
            if (InLane(lane, Ship.Position, 18))
            {
                if (lane.Hit.Add(-1)) Ship.HullHit(Sheltered(Ship.Position) ? power * .28f : power);
                if (lane.Strike is FleetStrike.Nets or FleetStrike.Ice) Ship.Velocity *= MathF.Pow(.38f, dt);
            }
            for (int i = 0; i < Allies.Length; i++) if (InLane(lane, Allies[i].Position, 14) && lane.Hit.Add(i)) Wound(Allies[i], power);
        }
        Lanes.RemoveAll(l => l.Fired && l.Live <= 0);
        foreach (var ally in Allies)
            if (AlliesInMelee(ally)) Wound(ally, 4 + Order.Tier * .22f);
    }
    bool AlliesInMelee(CommandHull ally) => ally.Afloat && ally.Hit <= 0 && Ship.Enemies.Any(e => e.Health > 0 && e.Stunned <= 0 && Vector2.DistanceSquared(e.Position, ally.Position) < 68 * 68);
    public static bool InLane(FleetLane lane, Vector2 p, float margin)
    {
        var delta = lane.To - lane.From; float t = Math.Clamp(Vector2.Dot(p - lane.From, delta) / Math.Max(1, delta.LengthSquared()), 0, 1);
        float radius = lane.Width + margin;
        return Vector2.DistanceSquared(p, lane.From + delta * t) < radius * radius;
    }
    void Strike()
    {
        salvos++;
        var target = salvos % 3 == 0 ? Ship.Position : Allies[(salvos + variant) % Allies.Length] is { Afloat: true } ally ? ally.Position : Ship.Position;
        var pattern = Field == FleetField.Captain || salvos % 3 == 0 ? Signature : salvos % 2 == 0 ? FleetStrike.Mortar : FleetStrike.Shear;
        float warning = Breach > 0 ? 2.65f : 2.05f;
        void Lane(FleetStrike strike, Vector2 a, Vector2 b, float width, float extra = 0) => Lanes.Add(new(strike, a, b, width, warning + extra));
        switch (pattern)
        {
            case FleetStrike.Mortar:
                Lane(pattern, target, target, 122); Lane(pattern, target + side * 174, target + side * 174, 90, .62f); break;
            case FleetStrike.Shear:
                Lane(pattern, target - heading * 320 - side * 60, target + heading * 260 + side * 40, 69);
                Lane(pattern, target + side * 250, target - heading * 95 - side * 140, 52, .78f); break;
            case FleetStrike.Nets:
                Lane(pattern, target - side * 244, target + side * 165, 97); break;
            case FleetStrike.Echo:
                Lane(pattern, target - heading * 220, target + heading * 230, 68);
                Lane(pattern, target - side * 255, target + side * 255, 71, 1.38f); break;
            case FleetStrike.Charge:
                var from = Field == FleetField.Captain ? EnemyHull : target - heading * 390;
                Lane(pattern, from, target + OceanWorld.Unit(target - from) * 150, 74); break;
            case FleetStrike.Ice:
                Lane(pattern, target - side * 118 - heading * 190, target + side * 68 + heading * 245, 57);
                Lane(pattern, target + side * 110 - heading * 185, target + side * 310 + heading * 225, 58, .26f); break;
            case FleetStrike.Swarm:
                Lane(pattern, target, target, 105); var lee = target - heading * 135; Lane(pattern, lee, lee, 100, .99f); break;
            default:
                Lane(pattern, target - side * 250 + heading * 115, target + side * 230 - heading * 110, 80);
                var leeSide = target + heading * 182; Lane(pattern, leeSide, leeSide, 110, .72f); break;
        }
    }
    void Commander(float dt)
    {
        var waypoint = Center + heading * (690 + 115 * MathF.Cos(Clock * .15f)) + side * (155 + 275 * MathF.Sin(Clock * .15f));
        if (GunsDown >= 2)
        {
            waypoint = Center + heading * (975 + 150 * MathF.Cos(Clock * .19f)) + side * (250 + 440 * MathF.Sin(Clock * .18f));
            Fog = Center + heading * (800 + 135 * MathF.Cos(Clock * .33f)) + side * (220 * MathF.Sin(Clock * .31f));
            Decoy = EnemyHull + side * 355 + heading * (130 + 95 * MathF.Sin(Clock * .4f));
        }
        var delta = waypoint - EnemyHull;
        EnemyBow = OceanWorld.Unit(delta, EnemyBow);
        EnemyHull = Ship.World.Slide(EnemyHull, EnemyHull + EnemyBow * Math.Min(delta.Length(), (EnemyStrength <= 0 ? 18 : GunsDown == 2 ? 105 : 53) * dt), 36);
        if (GunsDown >= 2) Stations[^1].Position = EnemyHull;
        foreach (var shot in Ship.Shots.Where(s => !s.Hostile && s.Life > 0))
        {
            if (GunsDown < 2)
            {
                var post = Stations.FirstOrDefault(s => s.Task == FleetTask.Cut && !s.Done && Vector2.DistanceSquared(s.Position, shot.Position) < 92 * 92);
                if (post == null) continue;
                post.Work += shot.Damage * (Breach > 0 ? .16f : .065f); shot.Life = 0;
                Ship.Events.Add(new("hit", post.Position, 12));
                post.Work = Math.Min(5.4f, post.Work);
            }
            else if (!FalseLight && Vector2.DistanceSquared(shot.Position, Decoy) < 96 * 96)
            { FalseLight = true; shot.Life = 0; Silver += 2; Ship.Events.Add(new("hit", Decoy, 10)); }
            else if (NamedSignal && ClearSight(Ship.Position, EnemyHull) && Vector2.DistanceSquared(shot.Position, EnemyHull) < 112 * 112)
            {
                EnemyStrength = Math.Max(0, EnemyStrength - shot.Damage * (Breach > 0 ? 1 : .66f)); shot.Life = 0; Ship.Events.Add(new("hit", EnemyHull, 14));
            }
        }

    }
}
