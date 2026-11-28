using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class FleetCommand
{
    public bool Sheltered(Vector2 point)
    {
        return Allies.Any(a => a.Afloat && a.Guard > 0 && Vector2.DistanceSquared(point, a.Position) < ShieldRange(a) * ShieldRange(a));
    }
    public float ShieldRange(CommandHull hull) => hull.Role == FleetRole.Tug ? 310 + reinforced * 25 : 170 + reinforced * 18;
    public string Duty(CommandHull a)
    {
        if (!a.Afloat) return "Adrift";
        if (a.People > 0) return $"Standing by · {a.People} for G handoff";
        if (a.Assignment < 0) return "With the cutter";
        var post = Stations[a.Assignment];
        if (post.Task == FleetTask.Ferry && post.Work >= 1) return post.Gate == 2 ? "Awaiting receiver" : post.Gate == 0 && post.AtFork ? "Holding at the fork" : "Under tow";
        if (a.Guard > 0) return "Braced at " + post.Title;
        return post.Title;
    }
    void MoveAlly(CommandHull ally, float dt)
    {
        ally.Hit = Math.Max(0, ally.Hit - dt);
        if (!ally.Afloat) return;
        ally.Cooldown -= dt; ally.Guard = Math.Max(0, ally.Guard - dt); ally.Signals = Math.Max(0, ally.Signals - dt);
        var post = ally.Assignment >= 0 ? Stations[ally.Assignment] : null;
        if (post?.Done == true && ally.People == 0) { Assign(ally, -1); post = null; }
        if (Field == FleetField.Refuge)
        {
            if (Vector2.DistanceSquared(ally.LastLead, Ship.Position) > 42 * 42)
            {
                ally.HomeWake.Enqueue(Ship.Position); ally.LastLead = Ship.Position;
            }
            while (ally.HomeWake.TryPeek(out var passed) && Vector2.DistanceSquared(passed, ally.Position) < 52 * 52) ally.HomeWake.Dequeue();
            var waypoint = ally.HomeWake.TryPeek(out var turn) ? turn : Ship.Position;
            if (Vector2.DistanceSquared(ally.Position, Ship.Position) > 98 * 98) Sail(ally, waypoint, dt);
            return;
        }
        if (ally.People > 0)
        {
            var source = post?.Position ?? ally.Position;
            var rendezvous = post == null ? Ship.Position + side * 80 : source + side * ((int)ally.Role - 1) * 72 - heading * 120;
            if (Vector2.DistanceSquared(ally.Position, rendezvous) > 50 * 50) Sail(ally, rendezvous, dt);
        }
        else if (post == null)
        {
            int i = (int)ally.Role;
            var fwd = new Vector2(MathF.Sin(Ship.Heading), -MathF.Cos(Ship.Heading));
            var broad = new Vector2(-fwd.Y, fwd.X);
            var berth = Ship.Position + fwd * (i == 1 ? -155 : -65) + broad * ((i - 1) * 138);
            if (Vector2.DistanceSquared(ally.Position, berth) > 90 * 90) Sail(ally, berth, dt);
        }
        else if (post.Task == FleetTask.Ferry && post.Work >= 1 && Vector2.DistanceSquared(ally.Position, post.Position) < 245 * 245)
        {
            int index = Stations.IndexOf(post);
            var destination = post.Gate == 0 ? towForks[index] : post.Berth;
            if (Vector2.DistanceSquared(ally.Position, destination) > 65 * 65) Sail(ally, destination, dt, true);
            var tow = ally.Position - post.Position;
            if (tow.LengthSquared() > 65 * 65) post.Position = Ship.World.Slide(post.Position, post.Position + OceanWorld.Unit(tow) * Math.Min(tow.Length() - 64, dt * 205), 19);
            if (post.Gate == 0 && Vector2.DistanceSquared(post.Position, towForks[index]) < 160 * 160) post.AtFork = true;
            if (post.Gate == 1 && Vector2.DistanceSquared(post.Position, post.Berth) < 168 * 168)
            { post.Gate = 2; Say(ally.Skipper + " requests the cutter’s signature at the receiving gate."); }
        }
        else
        {
            float distance = Vector2.Distance(ally.Position, post.Position);
            if (distance > (post.Task == FleetTask.Rally ? 108 : 88)) Sail(ally, post.Position, dt);
            if (distance < 133) Work(ally, post, dt);
        }
        if (ally.Cooldown <= 0 && ally.Guard <= 0)
        {
            float range = ally.Role == FleetRole.Sloop ? 475 : 250;
            var foe = Ship.Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(e.Position, ally.Position) < range * range)
                .MinBy(e => Vector2.DistanceSquared(e.Position, ally.Position));
            if (foe != null)
            {
                foe.Health = Math.Max(foe.HoldAt, foe.Health - (ally.Role == FleetRole.Sloop ? 11 : 5) - repairs * 2);
                Ship.Events.Add(new("arc", ally.Position, 0, foe.Position)); ally.Cooldown = ally.Role == FleetRole.Sloop ? 1.7f : 2.4f;
                if (foe.Health <= 0) Silver++;
            }
        }
    }
    void Sail(CommandHull ally, Vector2 destination, float dt, bool loaded = false)
    {
        while (ally.Bends.TryPeek(out var bend) && Vector2.DistanceSquared(ally.Position, bend) < 28 * 28) ally.Bends.Dequeue();
        var point = ally.Bends.TryPeek(out var next) ? next : destination;
        var delta = point - ally.Position; float gap = delta.Length();
        if (gap < 1) return;
        var aim = delta / gap;
        float speed = ally.Role switch { FleetRole.Tender => 242, FleetRole.Tug => 164, _ => 211 };
        if (loaded) speed *= ally.Role == FleetRole.Tug ? .90f : .64f;
        if (ally.People > 0) speed *= .84f;
        float travel = Math.Min(speed * dt, gap);
        ally.Bow = OceanWorld.Unit(Vector2.Lerp(ally.Bow, aim, Math.Min(1, dt * 3.8f)), aim);
        var moved = Ship.World.Slide(ally.Position, ally.Position + aim * travel, 24);
        if (Vector2.Dot(moved - ally.Position, aim) < travel * .20f) ally.Pinned += dt; else ally.Pinned = Math.Max(0, ally.Pinned - dt * .32f);
        ally.Position = moved;
        if (ally.Pinned > .40f)
        {
            ally.Pinned = 0;
            ShoalRoute.Plot(ally.Position, destination, p => Ship.World.IsWater(p, 26), ally.Bends);
        }
    }
    void Work(CommandHull ally, FleetPost post, float dt)
    {
        switch (post.Task)
        {
            case FleetTask.Rescue:
                if (!medicine.Contains((int)ally.Role) || Stations.IndexOf(post) == 1 && HouseLine != 2) return;
                ally.Progress += dt * (ally.Role == FleetRole.Tender ? 1.6f : 1);
                if (ally.Progress < 1.8f) return;
                ally.People = Math.Min(post.Stock, ally.Role == FleetRole.Tender ? 2 : 1); post.Stock -= ally.People; ally.Progress = 0;
                if (post.Stock == 0) post.Done = true;
                Say($"{ally.Skipper} has {ally.People} aboard and is making for the hospital."); break;
            case FleetTask.Brace:
                ally.Guard = 1; break;
            case FleetTask.Signal:
                if (ally.Signals <= 0)
                {
                    Breach = Math.Max(Breach, ally.Role == FleetRole.Sloop ? 5.8f : 2.8f); ally.Signals = ally.Role == FleetRole.Sloop ? 3.6f : 6.3f;
                    Ship.Events.Add(new("guard", ally.Position, 1));
                }
                break;
            case FleetTask.Ferry:
                ally.Progress += dt; if (ally.Progress > .75f) { post.Work = 1; ally.Progress = 0; }
                break;
            case FleetTask.Cut:
                float efficiency = ally.Role == FleetRole.Tug ? 1.55f : ally.Role == FleetRole.Sloop ? .84f : 1;
                post.Work += dt * efficiency * (Breach > 0 ? 1.7f : 1);
                post.Work = Math.Min(5.4f, post.Work);
                break;
            case FleetTask.Board:
                if (!NamedSignal) return;
                if (EnemyStrength <= 0) { Boarders = true; PressedCompany |= 1 << (int)ally.Role; return; }
                if (ally.Cooldown <= 0) { EnemyStrength = Math.Max(0, EnemyStrength - (ally.Role == FleetRole.Tug ? 19 : 12)); ally.Cooldown = 2.1f; Ship.Events.Add(new("pull", ally.Position, 1, EnemyHull)); }
                break;
        }
    }
    void BreakDevice(FleetPost post)
    {
        if (post.Done) return;
        post.Done = true; GunsDown++; Silver += 5; Ship.Events.Add(new("explosion", post.Position, 82));
        if (GunsDown < 2) { Say("One station strikes. The remaining gun turns toward the nearest pennant."); return; }
        Stations.Add(new(FleetTask.Board, Order.Boss, EnemyHull, EnemyHull)); Post = Stations.Count - 1;
        Say("Both devices are down. Send a boarding hull to the flagship. Vara can cut the last rig from the cutter.");
    }
    void Wound(CommandHull ally, float damage)
    {
        if (!ally.Afloat || ally.Hit > 0) return;
        if (Sheltered(ally.Position)) damage *= .29f;
        if (ally.Role == FleetRole.Tug) damage *= .75f;
        ally.Hull = Math.Max(0, ally.Hull - damage); ally.Hit = 1; Ship.Events.Add(new("hurt", ally.Position, damage));
        if (ally.Afloat) return;
        if (ally.People > 0)
        {
            Stations.Add(new(FleetTask.Rescue, "Abandoned launch", ally.Position, Refuge, ally.People)); ally.People = 0;
        }
        Assign(ally, -1); Say(ally.Name + " has lowered a distress flag. Bring the cutter and a repair kit alongside.");
    }
}
