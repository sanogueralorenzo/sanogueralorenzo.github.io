using System.Numerics;

namespace BoatsNBeasts.Core;

public enum DeckWork { Signal, Search, Chains, Pump, Passenger, Magazine, Captain }
public sealed record DeckSpar(Vector2 Center, Vector2 Half);
public sealed class PrizeGuard(Vector2 position, int role, int health)
{
    public Vector2 Position = position, Aim = Vector2.UnitY, From = position;
    public int Role = role, Health = health, MaxHealth = health;
    public float Tell, Recover = 1.05f, Stun, Dash;
    public bool Rim;
}
public sealed partial class PrizeBoarding
{
    public PrizeTheater Watch { get; }
    public int Room { get; private set; } = 1;
    public int Rooms => work.Length;
    public DeckWork Work => work[Room - 1];
    public string RoomName => Work switch
    {
        DeckWork.Signal => "The signal rail",
        DeckWork.Search => "The bonded lockers",
        DeckWork.Chains => "The chain gallery",
        DeckWork.Pump => "The flooded pump well",
        DeckWork.Passenger => "The passengers’ mess",
        DeckWork.Magazine => "The shot locker",
        _ => Watch.Operation == PrizeOperation.Flagship ? Watch.Order.Boss : "The quarterdeck"
    };
    public Vector2 Player { get; private set; }
    public Vector2 Mate { get; private set; }
    public Vector2 Passenger { get; private set; }
    public Vector2 Facing { get; private set; } = -Vector2.UnitY;
    public Vector2 Hitch { get; private set; }
    public Vector2 WorkPoint { get; private set; }
    public Vector2 Stash { get; private set; }
    public Vector2[] Lockers { get; private set; } = [];
    public int Lock { get; private set; }
    public Vector2 Hatch => new(-3.46f, -2.72f);
    public Vector2 Ladder => new(3.46f, -2.72f);
    public bool MateAtBrake { get; private set; }
    public bool Fixed { get; private set; }
    public bool Looted { get; private set; }
    public bool PassengerFree { get; private set; }
    public bool Freed { get; private set; }
    public bool Won { get; private set; }
    public bool Lost => Health <= 0;
    public int Health { get; private set; }
    public int MaxHealth { get; }
    public int Silver { get; private set; }
    public int Salves { get; private set; }
    public int Version { get; private set; }
    public int Bolts { get; private set; }
    public int Noise { get; private set; }
    public int GunThreat { get; private set; }
    public float Swing { get; private set; }
    public float Rope { get; private set; }
    public float Roll { get; private set; }
    public float Swell { get; private set; }
    public Vector2 HookEnd { get; private set; }
    public List<PrizeGuard> Guards { get; } = [];
    public List<DeckSpar> Spars { get; } = [];
    public string Call { get; private set; } = "";
    public string Instruction => Fixed ? Room == Rooms ? "Reach a rail hatch with your crew. E returns to the cutter." : "E at the port hatch for cover, or the starboard ladder for prize and pursuit." :
        Examining ? $"E at the {BenchNames[Examination - 1].ToLowerInvariant()}. Record {Watch.Exhibit.Mark}." : Work switch
        {
            DeckWork.Signal => "Q seats Lio at the signal brake. E lowers the relay flag at the far rail.",
            DeckWork.Search => $"Read the chalk stamps. E opens the locker marked {PrizeTheater.Seals[Lock]}.",
            DeckWork.Chains => "Q braces the paired winch. E cuts each shackle, then guide the prisoner to the rail.",
            DeckWork.Pump => "Q holds the pump handle. E opens the two discharge cocks on opposite sides.",
            DeckWork.Passenger => "E gathers the witnesses. Lead them to the back rail and use E again.",
            DeckWork.Magazine => "Vara needs a free hand. Q pins the lift brake, then E drops each shot basket.",
            _ => "Break the quartermaster’s guard. Lio’s Q catches a warning; Space cuts across the opening."
        };
    public Vector2 Objective => Fixed ? Hatch : Examining ? Bench : Work == DeckWork.Search ? Lockers[Lock] : Work == DeckWork.Captain ?
        Guards.FirstOrDefault(g => g.Role == 3 && g.Health > 0)?.Position ?? WorkPoint : RequiresBrace && !MateAtBrake ? Hitch : WorkPoint;
    public bool RequiresBrace => Work is DeckWork.Signal or DeckWork.Pump or DeckWork.Chains or DeckWork.Magazine;
    readonly DeckWork[] work;
    readonly int layout;
    float hurt, cut, rollWait, lineWait, clock, mateCut, hitRestore;
    Vector2 rollDirection;
    public PrizeBoarding(PrizeTheater watch, int seed)
    {
        Watch = watch; Method = ReadMaterial(watch.Exhibit.Item); layout = (seed & 7) + watch.Index;
        MaxHealth = 9 + Math.Min(3, watch.Allies) + (watch.Outfit == Loadout.Lifeboat ? 3 : 0);
        Health = Math.Max(2, MaxHealth - (int)Math.Ceiling(watch.Strain * .10)); Salves = watch.Covert ? 2 : 1;
        if (watch.Prisoners > 0) Salves++;
        Noise = watch.Covert ? 0 : 2;
        work = watch.Operation switch
        {
            PrizeOperation.Registry => [DeckWork.Signal, DeckWork.Search, DeckWork.Pump, DeckWork.Captain],
            PrizeOperation.Saboteur => [DeckWork.Magazine, DeckWork.Signal, DeckWork.Search, DeckWork.Captain],
            PrizeOperation.Courier => [DeckWork.Search, DeckWork.Passenger, DeckWork.Signal, DeckWork.Captain],
            PrizeOperation.ChainGang => [DeckWork.Pump, DeckWork.Chains, DeckWork.Passenger, DeckWork.Magazine, DeckWork.Captain],
            _ => [DeckWork.Signal, DeckWork.Magazine, DeckWork.Chains, DeckWork.Search, DeckWork.Passenger, DeckWork.Captain]
        };
        Build(false);
    }
    void Build(bool upper)
    {
        Fixed = Looted = MateAtBrake = PassengerFree = false; Bolts = Examination = 0; Guards.Clear(); Spars.Clear();
        Player = new(upper ? 2.48f : -2.45f, 2.25f); Mate = Player + new Vector2(.60f, 0); Facing = -Vector2.UnitY;
        var flip = (Room + layout) % 2 == 0 ? 1 : -1;
        Hitch = new(-flip * 2.76f, .76f); WorkPoint = new(flip * 2.48f, -1.57f); Stash = new(flip * 3.65f, 1.95f);
        Lock = (Room + Watch.Index + Watch.Mark.Stamp) % 4;
        Lockers = [new(-2.83f, -1.62f), new(-.99f, -1.62f), new(.99f, -1.62f), new(2.83f, -1.62f)];
        Passenger = WorkPoint;
        if (Work != DeckWork.Search)
        {
            Spars.Add(new(new(flip * .57f, -.05f), new(.53f, .74f)));
            Spars.Add(new(new(-flip * 1.6f, -.81f), new(.46f, .40f)));
        }
        else Spars.Add(new(new(0, .07f), new(.83f, .43f)));
        int count = 1 + (upper || Noise > 1 ? 1 : 0) + (Watch.Operation == PrizeOperation.Flagship ? 1 : 0);
        for (int i = 0; i < count; i++)
        {
            int role = (Room + i + Watch.Index) % 3;
            Guards.Add(new(new((i - 1) * 1.32f + .20f, -2.1f), role, role == 0 ? 3 : 2));
        }
        if (Work == DeckWork.Captain) Guards.Add(new(new(.11f, -1.51f), 3, Watch.Operation == PrizeOperation.Flagship ? 11 : 7));
        Call = upper ? "The ladder comes up behind the gun crews. They heard the boarding party." : Watch.Covert ? "The crew enters below the tiller, out of sight of the watch." : "The boarders are over the rail. Vara takes the first ladder.";
        Version++;
    }
    Vector2 Move(Vector2 at, Vector2 direction, float speed, float dt)
    {
        var p = Vector2.Clamp(at + direction * speed * dt, new(-4.03f, -2.93f), new(4.03f, 2.93f));
        foreach (var spar in Spars)
        {
            var d = p - spar.Center; float x = spar.Half.X + .18f - Math.Abs(d.X), y = spar.Half.Y + .18f - Math.Abs(d.Y);
            if (x <= 0 || y <= 0) continue;
            if (x < y) p.X += MathF.CopySign(x, d.X == 0 ? at.X - spar.Center.X : d.X);
            else p.Y += MathF.CopySign(y, d.Y == 0 ? at.Y - spar.Center.Y : d.Y);
        }
        return p;
    }
    Vector2 Follow(Vector2 at, Vector2 goal, float speed, float dt)
    {
        var d = goal - at; if (d.LengthSquared() < .018f) return at;
        var aim = Vector2.Normalize(d); var p = Move(at, aim, speed, dt);
        if (Vector2.Dot(p - at, aim) > dt * speed * .38f) return p;
        var side = new Vector2(-aim.Y, aim.X) * (at.X < 0 ? 1 : -1);
        return Move(at, side, speed, dt);
    }
    public void Tick(float dt, Vector2 move, bool slash, bool dodge, bool hook, bool interact, bool heal)
    {
        if (Won || Lost) return;
        clock += dt; hurt -= dt; cut -= dt; rollWait -= dt; lineWait -= dt; mateCut -= dt; hitRestore -= dt;
        Swing = Math.Max(0, Swing - dt); Rope = Math.Max(0, Rope - dt); Roll = Math.Max(0, Roll - dt);
        if (move.LengthSquared() > .01f) Facing = OceanWorld.Unit(move);
        if (dodge && rollWait <= 0) { Roll = .31f; rollWait = .84f; rollDirection = Facing; }
        Player = Move(Player, Roll > 0 ? rollDirection : OceanWorld.Unit(move), Roll > 0 ? 7.1f : Carrying ? 2.15f : 2.9f, dt);
        var mateTarget = MateAtBrake ? Hitch : Player - Facing * .54f + new Vector2(.32f, .12f);
        Mate = Follow(Mate, mateTarget, 4.1f, dt);
        if (PassengerFree) Passenger = Follow(Passenger, Player - Facing * .40f, 3.25f, dt);
        if (heal && Salves > 0 && Health < MaxHealth)
        { Salves--; Health = Math.Min(MaxHealth, Health + 4); Call = "Lio has the bandage tied before the deck rolls back."; Version++; }
        if (hook && lineWait <= 0) CommandLine();
        if (slash && cut <= 0)
        {
            Swing = .27f; cut = .48f;
            foreach (var foe in Guards.Where(g => g.Health > 0 && Vector2.Distance(g.Position, Player) < 1.51f))
                if (Vector2.Dot(Facing, OceanWorld.Unit(foe.Position - Player)) > -.16f)
                {
                    int damage = foe.Stun > 0 ? 3 : foe.Role == 3 && foe.Recover <= 0 ? 0 : 1;
                    Hit(foe, damage);
                }
        }
        if (!MateAtBrake && mateCut <= 0)
        {
            var nearby = Guards.Where(g => g.Health > 0 && Vector2.Distance(g.Position, Mate) < 1.06f).MinBy(g => g.Health);
            if (nearby != null) { Hit(nearby, 1); mateCut = 1.45f; }
        }
        foreach (var foe in Guards) if (foe.Health > 0) Guard(foe, dt);
        if (Work == DeckWork.Pump && !Fixed)
        {
            Swell = (MathF.Sin(clock * 1.08f) + 1) * .5f;
            if (Swell > .65f && Roll <= 0) Player = Move(Player, new Vector2(-.35f, .31f), Swell, dt);
        }
        if (Work == DeckWork.Captain && !Fixed && !Guards.Any(g => g.Role == 3 && g.Health > 0))
        { Fixed = true; Silver += 5; Call = "The quartermaster yields the hatch keys."; Version++; }
        if (interact) Interact();
    }
    void CommandLine()
    {
        if (RequiresBrace && Vector2.Distance(Player, Hitch) < 1.24f && !MateAtBrake)
        { MateAtBrake = true; Mate = Hitch; HookEnd = Hitch; Rope = .4f; lineWait = .55f; Call = "Lio has the brake. Both your hands are free."; Version++; return; }
        var foe = Guards.Where(g => g.Health > 0 && Vector2.Distance(g.Position, Player) < 3.25f + (Watch.Rigging * .10f))
            .OrderByDescending(g => g.Tell > 0).ThenBy(g => Vector2.DistanceSquared(Player, g.Position)).FirstOrDefault();
        if (foe == null) return;
        bool counter = foe.Tell > 0 || foe.Dash > 0;
        HookEnd = foe.Position; Rope = .42f; lineWait = Watch.Outfit == Loadout.Longline ? 1.7f : 2.3f;
        foe.Position = Move(foe.Position, OceanWorld.Unit(Player - foe.Position), counter ? 1.06f : .48f, 1);
        foe.Tell = foe.Dash = 0; foe.Stun = counter ? 1.65f : .72f; foe.Recover = 1.0f;
        if (counter) Hit(foe, 2); Call = counter ? "Lio catches the wind-up. Strike the open side." : "The line turns a guard away from the rail."; Version++;
    }
    void Hit(PrizeGuard g, int damage)
    {
        if (damage <= 0) return;
        g.Health = Math.Max(0, g.Health - damage);
        if (g.Health == 0) { Silver++; if (g.Role == 2) GunThreat = Math.Max(0, GunThreat - 1); }
        Version++;
    }
    void Guard(PrizeGuard g, float dt)
    {
        g.Stun -= dt; g.Recover -= dt; if (g.Stun > 0) return;
        var delta = Player - g.Position; float gap = delta.Length(); var dir = OceanWorld.Unit(delta);
        if (g.Dash > 0)
        {
            g.Dash -= dt; g.Position = Move(g.Position, g.Aim, 5.4f, dt);
            if (Vector2.Distance(g.Position, Player) < .76f) Hurt(2);
            return;
        }
        if (g.Tell > 0)
        {
            g.Tell -= dt; if (g.Tell > 0) return;
            g.Recover = g.Role == 3 ? 1.70f : 1.14f;
            if (g.Role == 1 || g.Role == 3 && !g.Rim) g.Dash = .36f;
            else if (g.Role == 2)
            {
                var line = Player - g.From;
                if (Vector2.Dot(line, g.Aim) > 0 && Math.Abs(line.X * g.Aim.Y - line.Y * g.Aim.X) < .48f) Hurt(2);
            }
            else if (gap < (g.Role == 3 ? 1.91f : 1.13f)) Hurt(g.Role == 3 ? 2 : 1);
            return;
        }
        float reach = g.Role == 2 ? 4.15f : g.Role == 1 ? 2.26f : g.Role == 3 ? 2.36f : 1.0f;
        if (g.Recover <= 0 && gap < reach)
        {
            g.Aim = dir; g.From = g.Position; g.Rim = !g.Rim; g.Tell = g.Role == 3 ? .87f : .73f;
        }
        else if (gap > (g.Role == 2 ? 2.3f : .69f)) g.Position = Follow(g.Position, Player, g.Role == 1 ? 1.67f : 1.22f, dt);
    }
    void Hurt(int amount)
    {
        if (hurt > 0 || Roll > 0) return;
        Health = Math.Max(0, Health - amount); hurt = 1.23f; Version++;
    }
    void Interact()
    {
        bool at(Vector2 p, float r = 1.08f) => Vector2.Distance(Player, p) < r;
        if (Fixed && (at(Hatch) || at(Ladder)))
        {
            if (Room == Rooms) { Won = true; Version++; return; }
            bool upper = at(Ladder); if (upper) { Silver += 3; Noise++; } else { Noise = Math.Max(0, Noise - 1); Health = Math.Min(MaxHealth, Health + 1); }
            Room++; Build(upper); return;
        }
        if (!Looted && at(Stash, .85f)) { Looted = true; Salves++; Silver += 2; Call = "A spare dressing and two silver in the bosun’s locker."; Version++; return; }
        if (Fixed || Work == DeckWork.Captain) return;
        if (Examining) { Examine(); return; }
        if (Work == DeckWork.Search)
        {
            int locker = Enumerable.Range(0, 4).MinBy(i => Vector2.DistanceSquared(Player, Lockers[i]));
            if (!at(Lockers[locker])) return;
            if (locker != Lock) { if (hitRestore > 0) return; hitRestore = 2; Noise++; Guards.Add(new(new(0, -2.58f), 1, 2)); Call = "A false ledger. The alarm bolt drops."; Version++; return; }
            BeginExamination(); return;
        }
        else if (!at(WorkPoint)) return;
        if (RequiresBrace && !MateAtBrake) { Call = "The brake springs back. Bring Lio to the rope post first."; Version++; return; }
        if (Work is DeckWork.Pump or DeckWork.Magazine or DeckWork.Chains && Bolts++ == 0)
        { WorkPoint = new(-WorkPoint.X, -2.07f); Call = "One side is clear. Take the other fitting."; Version++; return; }
        if (Work is DeckWork.Chains or DeckWork.Passenger)
        {
            if (!PassengerFree) { PassengerFree = true; Passenger = WorkPoint; WorkPoint = new(0, 2.23f); Call = "Keep the witness close. Take them to the launch rail."; Version++; return; }
            if (Vector2.Distance(Passenger, Player) > 1.65f) { Call = "The witness is still crossing the deck."; Version++; return; }
            Freed = true;
        }
        Fixed = true; MateAtBrake = false; Silver += 3; Call = Work == DeckWork.Search ? $"The locker holds {Watch.Exhibit.Item}. Its mark is {Watch.Exhibit.Mark}." : "The work is done. Choose the covered hatch or the prize ladder."; Version++;
    }
}
