using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class BluewaterCourse
{
    public int Sample { get; private set; }
    public int RequiredMark => (Leg + Station + Sample + Order.Tier) % 3;
    static readonly string[] Signs = ["split fin", "ring", "fork"];
    public string Sign => Signs[RequiredMark];
    public bool HasMarks => !Crossing && Phase == ChartPhase.Running && Job is SeaJob.Sound or SeaJob.Track;
    public Vector2 Mark(int number)
    {
        float a = (number - 1) * MathF.Tau / 3;
        return Target + new Vector2(MathF.Cos(a), MathF.Sin(a)) * 155;
    }
    public Vector2 Destination => Crossing ? RedPassage ? Prize : Shelter : Phase == ChartPhase.Boss ? BossCovered ? ShieldPoint : Captain?.Position ?? Target :
        HasMarks && Vector2.Distance(Target,Ship.Position) < 790 ? Mark(RequiredMark) : Target;
    public string JobName => Crossing ? "Choose a crossing" : Phase switch
    {
        ChartPhase.Boss => BossCovered ? "Open the armor" : Order.Boss,
        ChartPhase.Port => Order.Id == "north-return" ? "Light the home lamp" : Order.Duty == SeaDuty.Convoy ? "Signal the fleet" : "Make your report",
        _ => Job switch
        {
            SeaJob.Tow => $"Tow the {Writ.Cargo}",
            SeaJob.Guide => "Thread the gate",
            SeaJob.Salvage => $"Raise the {Writ.Cargo}",
            SeaJob.Unload => $"Land the {Writ.Cargo}",
            SeaJob.Track => "Read the trail",
            SeaJob.Bait => "Lay the scent pot",
            SeaJob.DriveOff => "Break the patrol",
            SeaJob.Sound => "Triangulate the channel",
            SeaJob.Cut => "Break the chain boom",
            SeaJob.Relay => "Hoist the all-clear",
            _ => "Bring in the watch"
        }
    };
    public string HelmOrder => Crossing ? CrossingOrder : Phase switch
    {
        ChartPhase.Port => $"Come alongside {Writ.Berth} and press Q.",
        ChartPhase.Boss when BossCovered => Order.Duty switch
        {
            SeaDuty.Convoy => "Bring the convoy inside the signal ring. Q orders a clay-boat volley.",
            SeaDuty.Salvage => "Hook the yellow wreck sling with Q to tear the plating away.",
            SeaDuty.Hunt => "Wait for the quarry to wind up. Q catches it in the charge.",
            SeaDuty.Sounding => "Set Lio over the sounding float and press Q to break the echo.",
            _ => "Fire at the floating magazine to blow off the commander's armor."
        },
        ChartPhase.Boss => "The armor is open. Lead the target, or turn side-on for a broadside.",
        _ => Job switch
        {
            SeaJob.Tow => "Sail alongside the waiting lighter. Q passes its painter to Lio.",
            SeaJob.Guide => "Bring the convoy through the beacon ring together.",
            SeaJob.Salvage => $"Q hooks the {Writ.Cargo}. Protect it all the way to its berth.",
            SeaJob.Unload => "Bring the lighter alongside the gantry and press Q.",
            SeaJob.Track => $"Trace the {Writ.Cargo} to the {Sign} marker with Q.",
            SeaJob.Sound => $"Sound the {Sign} buoy with Q. Readings {Sample}/2.",
            SeaJob.Bait => "Come upwind of the scent pot. Q sets it adrift for the hunters.",
            SeaJob.DriveOff => guardsSent ? "Break the pennant leader. Q interrupts a lunge." : "Intercept the patrol at its pennant.",
            SeaJob.Cut => "Hold Space in gun range or click the chain winch. Dodge its mortar.",
            SeaJob.Relay => "Take the signal tower's line with Q to clear the next reach.",
            _ => "Come alongside and press Q to take off the watch."
        }
    };
    public Vector2? AutomaticAim()
    {
        if (HasGunneryTarget && Vector2.Distance(Ship.Position,CannonTarget) < 645) return CannonTarget;
        var nearest = Ship.Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(Ship.Position,e.Position) < 630 * 630)
            .MinBy(e => Vector2.DistanceSquared(Ship.Position,e.Position));
        if (nearest == null) return null;
        return nearest.Position;
    }

    Enemy? pennant;
    int bountyKills;
    void TickJob(bool hook)
    {
        Vector2 ship = Ship.Position;
        float distance = Vector2.Distance(ship,Target);
        patrolDistance += Vector2.Distance(ship,beforeTravel);
        beforeTravel = ship;
        if (patrolDistance > (RedPassage ? 830 : 1270))
        {
            patrolDistance = 0;
            if (Ship.Enemies.Count < 4 + Math.Min(Order.Tier,6)) Ship.Spawn(Raider(alertCount++));
        }
        if (Ship.Kills >= bountyKills + 4)
        {
            Purse += (Ship.Kills - bountyKills) / 4;
            bountyKills = Ship.Kills - Ship.Kills % 4;
        }
        if (distance < 700 && !guardsSent)
        {
            guardsSent = true;
            int count = (RedPassage ? 2 : 1) + Math.Min(Order.Tier / 3,2);
            for (int j=0;j<count;j++)
            {
                float a = random.Range(0,MathF.Tau);
                var spawn = Target + new Vector2(MathF.Cos(a),MathF.Sin(a)) * (330 + j*70);
                bool named = j == 0 && Job == SeaJob.DriveOff;
                var raider = Ship.DropPatrol(named ? EnemyKind.Serpent : Raider(j+Station),spawn, 1 + Math.Min(Order.Tier,8)*.06f,named);
                if (named) pennant = raider;
            }
        }
        if (Job == SeaJob.Cut && distance < 590)
        {
            Threaten(Target,Ship.Position,3.8f);
            if (GunStrikes(Target))
            {
                Ship.Events.Add(new("explosion",Target,110));
                Step();
                return;
            }
        }
        if (Job == SeaJob.DriveOff && guardsSent && (pennant == null || pennant.Health <= 0)) { Step(); return; }
        if (Job == SeaJob.Guide && distance < 165 && fleet.All(b => Vector2.Distance(b.Position,Target) < 640)) { Step(); return; }
        if (!hook) return;
        if (HasMarks)
        {
            int nearest = Enumerable.Range(0,3).MinBy(i => Vector2.DistanceSquared(Mark(i),ship));
            if (Vector2.Distance(Mark(nearest),ship) < 130)
            {
                HookAt(Mark(nearest));
                if (nearest != RequiredMark)
                {
                    if (HookCooldown <= 0)
                    {
                        Ship.Spawn(EnemyKind.Puffer); HookCooldown = 2;
                        Say("Lio    Wrong cut on the float. Something's coming up from beneath it!");
                    }
                }
                else if (Job == SeaJob.Sound && Sample == 0) { Sample++; Purse++; Say($"Lio    Got the first depth. Take me across to the {Sign}."); }
                else Step();
                return;
            }
        }
        else if (distance < 210 && Job is SeaJob.Tow or SeaJob.Salvage or SeaJob.Unload or SeaJob.Bait or SeaJob.Relay or SeaJob.Relieve)
        {
            HookAt(Target);
            if (Job is SeaJob.Tow or SeaJob.Salvage)
            {
                if (fleet.Count < 3) fleet.Add(new(Target, 110 + 7 * Order.Tier, Job == SeaJob.Salvage));
                else
                {
                    var exchanged=fleet.MinBy(b=>b.Health)!;
                    fleet.Remove(exchanged);
                    fleet.Add(new(Target, 110 + 7 * Order.Tier, Job == SeaJob.Salvage));
                }
            }
            if (Job == SeaJob.Unload && SalvageTow)
            {
                fleet.RemoveAll(b=>b.Prize); Purse += 3;
            }
            if (Job == SeaJob.Relieve) {Kits++;Ship.Patch(12);}
            if (Job == SeaJob.Bait)
            {
                Ship.Spawn(EnemyKind.Ray);
                Ship.Events.Add(new("explosion",Target,100));
            }
            Step();
            return;
        }
        HookEnemy();
    }

    EnemyKind Raider(int index) => (Country.Climate, (index + Leg + (int)Order.Duty) % 3) switch
    {
        (SeaClimate.Orchard or SeaClimate.Court, 0) => EnemyKind.Ray,
        (SeaClimate.Shelf or SeaClimate.Choir, 0) => EnemyKind.Puffer,
        (SeaClimate.Delta or SeaClimate.Loom, 1) => EnemyKind.Serpent,
        (_, 0) => EnemyKind.Crab,
        (_, 1) => RedPassage || Order.Duty == SeaDuty.Hunt ? EnemyKind.Serpent : EnemyKind.Ray,
        _ => EnemyKind.Puffer
    };

    void Step()
    {
        Purse += RedPassage ? 4 : 2;
        Ship.Xp += 4 + Math.Min(5,Order.Tier);
        Sample = 0;
        pennant = null;
        Alarm = 0;
        Station++;
        if (Station < jobs.Length) { SetStation(); Say(HelmOrder); return; }
        foreach (var enemy in Ship.Enemies) enemy.Marked = false;
        if (Leg < Order.Legs) { Phase = ChartPhase.Refit; return; }
        Target = FindWater(Ship.Position + course * 920, 380);
        Phase = ChartPhase.Boss;
        Weather.Set(Target,Leg,Station);
        Say($"Vara    {Order.Boss}. The port's last guard is turning out to meet us.");
    }

    void HookAt(Vector2 target)
    {
        HookEnd = target;
        HookTime = .55f;
        Ship.Events.Add(new("pull",Ship.Position,2,target));
    }

    void HookEnemy()
    {
        if (HookCooldown > 0) return;
        var target = Ship.Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(e.Position,Ship.Position) < HookReach * HookReach)
            .OrderByDescending(e => e.Marked).ThenBy(e => Vector2.DistanceSquared(e.Position,Ship.Position)).FirstOrDefault();
        if (target == null) return;
        HookAt(target.Position);
        Ship.Grapple(target);
        HookCooldown = Math.Max(1.5f, 5.4f - lineRank * .55f - (Outfit == Loadout.Longline ? 1 : 0));
    }

    bool GunStrikes(Vector2 center)
    {
        float remaining=GateHealth;
        bool broken=DamageProp(center,ref remaining);
        GateHealth=remaining;
        return broken;
    }

    bool DamageProp(Vector2 center,ref float remaining)
    {
        foreach (var shot in Ship.Shots)
        {
            if (shot.Hostile || shot.Kind is not (WeaponKind.Cannon or WeaponKind.Harpoon) || shot.Life <= 0) continue;
            if (Vector2.DistanceSquared(shot.Position,center) > 80*80) continue;
            remaining -= shot.Damage;
            shot.Life = 0;
            Ship.Events.Add(new("hit",center,shot.Damage));
        }
        return remaining <= 0;
    }

    void Threaten(Vector2 origin, Vector2 target, float cadence)
    {
        if (Alarm > 0) return;
        Alarm = cadence;
        float flight = 1.65f;
        Ship.Shots.Add(new() { Hostile = true, Position = origin, Previous = origin, Target = target,
            Velocity = (target-origin)/flight, FlightDuration = flight, Damage = 12 + Order.Tier, Life = flight, Radius = 108 });
    }

    void TickCaptain(bool hook,float dt)
    {
        if (Captain == null)
        {
            if (Vector2.DistanceSquared(Ship.Position,Target) > 1000*1000) return;
            var kind = Order.Duty == SeaDuty.Hunt ? EnemyKind.Serpent : EnemyKind.Leviathan;
            Captain = Ship.DropPatrol(kind,Target,1.7f + Math.Min(9,Order.Tier)*.22f,true);
            if (Captain == null) return;
            Captain.Health = Captain.MaxHealth = Math.Max(100, Captain.MaxHealth - 11 * trailClues);
            Cover();
        }
        if (Captain.Health <= 0)
        {
            foreach (var e in Ship.Enemies) e.Health = 0;
            Ship.Shots.Clear();
            Phase = ChartPhase.Port;
            Target = FindWater(Ship.Position + course*780,190);
            Purse += 8;
            Say("Lio    The mouth of the port is clear. Take the tender's line.");
            return;
        }
        if (!BossCovered && Seals == 1 && Captain.Health < Captain.MaxHealth * .53f) Cover();
        CommanderAttack(dt);
        if (BossCovered)
        {
            bool opened = false;
            if (Order.Duty == SeaDuty.Hunt) ShieldPoint = Captain.Position;
            float distance = Vector2.Distance(Ship.Position,ShieldPoint);
            if (Order.Duty == SeaDuty.Blockade) opened = GunStrikes(ShieldPoint);
            else if (hook)
            {
                opened = Order.Duty switch
                {
                    SeaDuty.Convoy => distance < 250 && fleet.All(b => Vector2.Distance(b.Position,ShieldPoint) < 700),
                    SeaDuty.Salvage => distance < HookReach,
                    SeaDuty.Hunt => distance < HookReach && (Captain.Telegraph > 0 || Captain.Dash > 0 || Captain.Stunned > 0 || Captain.AttackClock < 1.0f),
                    _ => distance < 180
                };
            }
            if (opened)
            {
                HookAt(ShieldPoint);
                Captain.Armor = 0; Captain.Stunned = 3.2f; BossCovered = false; Seals++;
                Captain.HoldAt = Seals == 1 ? Captain.MaxHealth * .5f : 0;
                Ship.Events.Add(new("explosion",ShieldPoint,145));
                Say("Vara    There's daylight through the plate. All guns together!");
                return;
            }
            if (Order.Duty is SeaDuty.Blockade or SeaDuty.Sounding && distance < 500) Threaten(ShieldPoint,Ship.Position+Ship.Velocity * .28f,4.6f);
        }
        if (hook) HookEnemy();
    }

    void Cover()
    {
        BossCovered = true;
        Captain!.Armor = 1;
        var side = new Vector2(-course.Y,course.X);
        ShieldPoint = FindWater(Captain.Position + side * (Seals == 0 ? 310 : -360),110);
        GateHealth = 34 + Order.Tier * 5;
        if (Seals > 0) Ship.Spawn(Raider(Seals));
        Say(HelmOrder);
    }
}
