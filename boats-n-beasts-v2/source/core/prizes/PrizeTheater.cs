using System.Numerics;

namespace BoatsNBeasts.Core;

public enum PrizePhase { Muster, Witness, Inquiry, Search, Hail, Chase, Board, Landfall, Crossing, Refit, Assize, Return, Won, Lost }
public enum PrizeOperation { Registry, Saboteur, SignalFort, ReliefFleet, Courier, ChainGang, Flagship }
public sealed class PrizeContact(string name, int color, int rig, int stamp, Vector2[] route)
{
    public string Name { get; } = name;
    public int Color { get; } = color;
    public int Rig { get; } = rig;
    public int Stamp { get; } = stamp;
    public Vector2[] Route { get; } = route;
    public Vector2 Position = route[0], Bow = Vector2.UnitY;
    public int Waypoint = 1;
    public float Gear = 50;
    public bool Inspected, Released;
    public string Marks => $"{PrizeTheater.Flags[Color]} cloth · {PrizeTheater.Rigs[Rig]} · {PrizeTheater.Seals[Stamp]}";
}

public sealed partial class PrizeTheater
{
    public static readonly string[] Flags = ["saffron", "coral", "sea-green", "violet"];
    public static readonly string[] Rigs = ["split topsail", "double yard", "short gaff", "wing sprit"];
    public static readonly string[] Seals = ["a key", "a cup", "a gull", "a leaf"];
    public static readonly string[] Calls = ["one low bell", "two high bells", "three even bells"];
    static readonly string[] Names = ["Supper Bell", "Kettlewing", "Brass Aunt", "Old Parsley", "Sixth Window", "June Kite", "Pepper Roll", "North Apron", "Little Wager", "Salt Finch", "Cork Child", "Open Door"];
    public CampaignOrder Order { get; }
    public Voyage Ship { get; }
    public SeaCountry Country { get; }
    public Loadout Outfit { get; }
    public PrizePhase Phase { get; private set; } = PrizePhase.Muster;
    public PrizeOperation[] Operations { get; }
    public PrizeOperation Operation => Operations[Math.Min(Index, Operations.Length - 1)];
    public int Index { get; private set; }
    public int Purse { get; private set; }
    public int Kits { get; private set; }
    public int Strain { get; private set; }
    public PrizeAssize? Assize { get; private set; }
    public PrizeInquiry? Inquiry { get; private set; }
    public CaseEvidence Exhibit => Order.Evidence ?? new("the original dispatch", "the owner’s thumbprint", "The dispatch precedes the seizure stamp.");
    public bool Found { get; private set; }
    public int Dockets { get; private set; }
    public int Evidence { get; private set; }
    public int Prisoners { get; private set; }
    public int Alarm { get; private set; }
    public int Rigging { get; private set; }
    public int Allies { get; private set; }
    public int QuietEntries { get; private set; }
    public bool Covert { get; private set; }
    public int Report { get; private set; }
    public int CorrectCall { get; private set; }
    public int ContactCursor { get; private set; }
    public Vector2 Home { get; }
    public Vector2 Witness { get; private set; }
    public Vector2 Cache { get; private set; }
    public Vector2 Exit { get; private set; }
    public Vector2 Tow { get; private set; }
    public float TowHull { get; private set; } = 100;
    public bool Foraged { get; private set; }
    public PrizeContact[] Contacts { get; private set; } = [];
    public PrizeContact? Queried { get; private set; }
    public PrizeContact Mark => Contacts[mark];
    public Vector2 Wind { get; private set; } = Vector2.UnitX;
    public string Dispatch { get; private set; } = "";
    public float DispatchTime { get; private set; }
    public int Version { get; private set; }
    public float HookFlash { get; private set; }
    public Vector2 HookEnd { get; private set; }
    public bool Wounded => Strain > 0;
    public float HealthFraction => Math.Clamp(Ship.Health / Ship.MaxHealth, 0, 1);
    public string RegionName => string.IsNullOrEmpty(Order.Island) ? Order.Region : Order.Island;
    public string WatchName => Operation switch
    {
        PrizeOperation.Registry => "The dispatch desk",
        PrizeOperation.Saboteur => "The false pennant",
        PrizeOperation.SignalFort => "The signal house",
        PrizeOperation.ReliefFleet => "The relief convoy",
        PrizeOperation.Courier => "The runner’s packet",
        PrizeOperation.ChainGang => "The floating prison",
        _ => Order.Boss
    };
    public string PublicClue => Contacts.Length == 0 ? "" : $"{Flags[Mark.Color]} cloth and {Rigs[Mark.Rig]}. The customs stamp shows {Seals[Mark.Stamp]}.";
    public string Instructions => Phase switch
    {
        PrizePhase.Witness => Operation switch
        {
            PrizeOperation.SignalFort => "Q at the pilot steps to land a party at the signal house.",
            PrizeOperation.ReliefFleet => "Q alongside the relief tender to take the convoy through.",
            _ => "Meet the packet boat. Q takes down the public marks and reply."
        },
        PrizePhase.Inquiry => Inquiry!.Directions,
        PrizePhase.Assize => Assize!.Instruction,
        PrizePhase.Search => $"Find {Flags[Mark.Color]} cloth with {Rigs[Mark.Rig]}. Q reads the hull stamp alongside.",
        PrizePhase.Chase => "Q hails alongside. To board by force, shoot out the rigging and Q Lio across.",
        PrizePhase.Return => HasFinalTow ? "Bring the recovered ship through the pilot gates, then Q at the harbor tender." : "Sail to the tender and press Q to recover your crew.",
        _ => ""
    };
    public bool HasFinalTow { get; private set; }
    public int ReturnGate { get; private set; }
    public Vector2[] Gates { get; private set; } = [];
    public Vector2 Destination => Phase switch
    {
        PrizePhase.Witness => Witness,
        PrizePhase.Inquiry => Inquiry!.Bearing,
        PrizePhase.Assize => Assize!.Goal,
        PrizePhase.Search => Contacts[ContactCursor].Position,
        PrizePhase.Chase => Mark.Position,
        PrizePhase.Return => ReturnGate < Gates.Length ? Gates[ReturnGate] : Exit,
        _ => Ship.Position
    };
    public bool AtChild => Phase is PrizePhase.Landfall or PrizePhase.Crossing or PrizePhase.Board;
    readonly OceanWorld pilot;
    SeedRandom random;
    readonly int seed;
    int mark, homeGateGuard = -1;
    float clock, alarmClock, shotClock, lineClock, turnClock, patchClock;
    Vector2 bearing, lastTow;
    float towPinned;
    readonly Queue<Vector2> returnWake = [];
    internal void AwardPrize(int silver) => Purse += silver;
    internal void RaiseAlarm() => Alarm = Math.Min(8, Alarm + 1);
    internal bool SpendPilot() { if (Allies <= 0) return false; Allies--; return true; }
    internal void RecordFinding() { if (Found) return; Found = true; Evidence++; }
    internal void SealDocket(bool witness, bool original, bool escorted)
    {
        Dockets++; if (original) Evidence++; if (witness) Prisoners++; if (escorted) Allies++;
        Report = 1; Phase = PrizePhase.Search; Purse += 4;
        Say($"The pilot compares both accounts. Seek {Flags[Mark.Color]} cloth and {Rigs[Mark.Rig]}. Reply with {Calls[CorrectCall]}.");
    }
    public void DeployAlly() { if (Phase == PrizePhase.Inquiry) Inquiry?.SendPilot(); }
    internal static Vector2 Trail(Voyage ship, Vector2 follower, Queue<Vector2> wake, ref Vector2 last, ref float pinned, float dt, float length)
    {
        if (Vector2.DistanceSquared(ship.Position, last) > 28 * 28) { wake.Enqueue(ship.Position); last = ship.Position; }
        while (wake.Count > 0 && Vector2.DistanceSquared(follower, wake.Peek()) < 32 * 32) wake.Dequeue();
        var delta = ship.Position - follower;
        if (delta.Length() <= length && wake.Count < 5) return follower;
        var aim = wake.Count == 0 ? ship.Position : wake.Peek();
        var to = aim - follower; float distance = to.Length();
        if (distance < 1) return follower;
        float travel = Math.Min(distance, Math.Min(ship.Speed * 1.9f, Math.Max(75, (delta.Length() - length * .7f) * 3)) * dt);
        var result = ship.World.Slide(follower, follower + to / distance * travel, 18);
        bool caught = travel > .024f && Vector2.Dot(result - follower, to / distance) < travel * .17f;
        pinned = caught ? pinned + dt : Math.Max(0, pinned - dt * .26f);
        if (pinned > .56f)
        {
            pinned = 0;
            if (ShoalRoute.Plot(result, ship.Position, p => ship.World.IsWater(p, 22), wake)) last = ship.Position;
        }
        return result;
    }
    public PrizeTheater(CampaignOrder order, int trial, int stores, Loadout outfit, BoatKind hull)
    {
        Order = order; seed = trial; Outfit = outfit;
        Country = SeaCountry.At(order.Region, order.Island);
        var districtHash = 23u; foreach (char letter in order.Id) districtHash = unchecked(districtHash * 31 + letter);
        random = new((uint)trial ^ districtHash);
        Ship = new((uint)trial, hull, 1) { Charted = true, BroadsideRig = outfit == Loadout.Broadside, HullRank = Math.Clamp(stores, 0, 2) };
        Ship.Weapons[(int)WeaponKind.Cannon] = Math.Max(1, Ship.Weapons[(int)WeaponKind.Cannon]);
        Ship.Health = Ship.MaxHealth; Kits = 1 + Math.Clamp(stores, 0, 2) + (outfit == Loadout.Lifeboat ? 2 : 0);
        pilot = new(Ship.World.Seed);
        Home = Water(new Vector2(12800 + order.Tier * 2500, -8000 - (districtHash % 5) * 3200), 170); Ship.Position = Home; Ship.World.Stream(Home);
        Operations = string.IsNullOrEmpty(order.Island) ?
            [PrizeOperation.Registry, PrizeOperation.Saboteur, PrizeOperation.SignalFort, PrizeOperation.ReliefFleet, PrizeOperation.Courier, PrizeOperation.ChainGang, PrizeOperation.Flagship] :
            [PrizeOperation.Registry, PrizeOperation.SignalFort, PrizeOperation.ReliefFleet, PrizeOperation.ChainGang, PrizeOperation.Flagship];
    }
    Vector2 Water(Vector2 near, float radius)
    {
        pilot.Stream(near);
        for (int ring = 0; ring <= 16; ring++)
            for (int j = 0; j < (ring == 0 ? 1 : 16); j++)
            {
                float a = MathF.Tau * j / 16 + ring * .42f; var p = near + new Vector2(MathF.Cos(a), MathF.Sin(a)) * ring * 96;
                if (pilot.IsWater(p, radius)) return p;
            }
        return Ship.Position;
    }
    public void Start(int contract)
    {
        if (Phase != PrizePhase.Muster) return;
        if (contract == 0) Kits++;
        if (contract == 1) { Rigging++; Ship.ReloadRank++; }
        if (contract == 2) { Allies++; Evidence++; }
        BeginReach();
    }
    void BeginReach()
    {
        Inquiry = null; Report = 0; mark = random.Index(4); CorrectCall = random.Index(3); ContactCursor = 0; Foraged = false; Covert = false; Queried = null;
        float a = random.Range(0, MathF.Tau); bearing = new(MathF.Cos(a), MathF.Sin(a)); Wind = new(-bearing.Y, bearing.X);
        var center = Water(Ship.Position + bearing * 1600, 260);
        Witness = Water(Ship.Position + bearing * 750 + Wind * 210, 142);
        Cache = Water(Ship.Position - Wind * 580 + bearing * 375, 125);
        int flag = random.Index(4), rig = random.Index(4), stamp = random.Index(4), name = random.Index(Names.Length);
        Contacts = Enumerable.Range(0, 4).Select(n =>
        {
            int relative = (n - mark + 4) % 4;
            var from = Water(center + bearing * ((n % 2) * 410 - 190) + Wind * ((n / 2) * 530 - 280), 115);
            Vector2[] route = [from, Water(from + bearing * (520 + n * 55) + Wind * 170, 115), Water(from + bearing * 340 - Wind * 370, 115), Water(from - bearing * 280 - Wind * 265, 115)];
            return new PrizeContact(Names[(name + n * 3) % Names.Length], relative == 2 ? (flag + 1) % 4 : flag, relative == 3 ? (rig + 2) % 4 : rig, relative == 1 ? (stamp + 1) % 4 : stamp, route);
        }).ToArray();
        Phase = PrizePhase.Witness; Version++; alarmClock = 3; turnClock = 12;
        Say($"{WatchName}. The packet crew have news of the next sailing.");
    }
    public void Cycle()
    {
        if (Phase == PrizePhase.Inquiry) { Inquiry!.NextBearing(); return; }
        if (Phase == PrizePhase.Assize) { Assize!.Cycle(); return; }
        if (Phase != PrizePhase.Search) return;
        for (int i = 0; i < Contacts.Length; i++)
        { ContactCursor = (ContactCursor + 1) % Contacts.Length; if (!Contacts[ContactCursor].Released) break; }
        Version++;
    }
    public void Say(string line) { Dispatch = line; DispatchTime = 4; Version++; }
    public bool Patch()
    {
        if (Kits == 0 || patchClock > 0 || Ship.Health >= Ship.MaxHealth && TowHull >= 100) return false;
        Kits--; patchClock = 2; Ship.Patch(Outfit == Loadout.Lifeboat ? 49 : 32); TowHull = Math.Min(100, TowHull + 29);
        Say("Vara plugs the sprung seam. The remaining canvas stays dry."); return true;
    }
    public void Tick(float dt, SailInput input, bool hook)
    {
        if (Phase is not (PrizePhase.Witness or PrizePhase.Inquiry or PrizePhase.Search or PrizePhase.Chase or PrizePhase.Assize or PrizePhase.Return)) return;
        DispatchTime = Math.Max(0, DispatchTime - dt); HookFlash = Math.Max(0, HookFlash - dt); lineClock -= dt; patchClock -= dt; shotClock -= dt; clock += dt;
        if (Ship.Mode == VoyageMode.Upgrade) return;
        var priorSilver = Ship.SilverEarned;
        Ship.EscortPosition = HasFinalTow ? Tow : null;
        Ship.Tick(dt, input); Purse += Ship.SilverEarned - priorSilver;
        if (Ship.Health <= 0) { Lose("The cutter settles. Lio brings the living crew back in the launch."); return; }
        float weather = Vector2.Dot(OceanWorld.Unit(Ship.Velocity), Wind);
        if (weather > .62f) Ship.Boost = Math.Min(100, Ship.Boost + dt * 6);
        if (Phase == PrizePhase.Return) { Homeward(dt, hook); return; }
        if (Phase == PrizePhase.Assize) { Assize!.Tick(dt, hook); return; }
        if (Phase == PrizePhase.Inquiry) { Inquiry!.Tick(dt, hook); if (hook && Phase == PrizePhase.Inquiry) ThrowLine(); return; }
        foreach (var craft in Contacts)
        {
            if (craft.Released) continue;
            var to = craft.Route[craft.Waypoint] - craft.Position;
            if (to.LengthSquared() < 86 * 86) { craft.Waypoint = (craft.Waypoint + 1) % craft.Route.Length; to = craft.Route[craft.Waypoint] - craft.Position; }
            var desired = OceanWorld.Unit(to);
            craft.Bow = OceanWorld.Unit(Vector2.Lerp(craft.Bow, desired, Math.Min(1, dt * 2.2f)), desired);
            float pace = Phase == PrizePhase.Chase && craft == Mark ? Math.Clamp(craft.Gear * 2.7f, 12, 152) : 51 + craft.Rig * 6;
            var drift = craft.Bow * pace + Wind * 9;
            var next = pilot.Slide(craft.Position, craft.Position + drift * dt, 30);
            if (Vector2.DistanceSquared(next, craft.Position) < dt * dt * 30) craft.Waypoint = (craft.Waypoint + 1) % 4;
            craft.Position = next;
        }
        turnClock -= dt;
        if (turnClock <= 0)
        {
            Wind = Vector2.TransformNormal(Wind, Matrix3x2.CreateRotation(.72f)); turnClock = 19;
            if (Phase == PrizePhase.Chase) Mark.Waypoint = (Mark.Waypoint + 1) % 4;
        }
        if (Phase == PrizePhase.Witness && hook && Near(Witness, 196))
        {
            if (Operation == PrizeOperation.SignalFort) { Phase = PrizePhase.Landfall; Version++; return; }
            if (Operation == PrizeOperation.ReliefFleet) { Phase = PrizePhase.Crossing; Version++; return; }
            Inquiry = new(this, Water, bearing, seed + Index * 7 + Mark.Stamp); Phase = PrizePhase.Inquiry;
            Say(Inquiry.Title + ". " + Exhibit.Item + " is named in the watch order."); return;
        }
        if (hook && !Foraged && Near(Cache, 155))
        {
            Foraged = true; Kits++; Purse += 3; Ship.Patch(9); Say("Lio brings up dry canvas and three silver from the pilot’s cache."); return;
        }
        if (Phase == PrizePhase.Search && hook)
        {
            var focused = Contacts[ContactCursor];
            var close = !focused.Released && Near(focused.Position, 190) ? focused : Contacts.Where(c => !c.Released && Near(c.Position, 190)).MinBy(c => Vector2.DistanceSquared(Ship.Position, c.Position));
            if (close != null) { Queried = close; close.Inspected = true; Phase = PrizePhase.Hail; Version++; return; }
        }
        if (Phase == PrizePhase.Chase)
        {
            if (Near(Mark.Position, 600) && shotClock <= 0)
            {
                Ship.Lob(Mark.Position, Ship.Position + Ship.Velocity * .42f, 9 + Math.Min(7, Order.Tier), 97); shotClock = 5.2f;
            }
            foreach (var shot in Ship.Shots.Where(s => !s.Hostile && s.Life > 0 && s.Kind is WeaponKind.Cannon or WeaponKind.Harpoon or WeaponKind.Arcane))
                if (Vector2.DistanceSquared(shot.Position, Mark.Position) < 90 * 90)
                { Mark.Gear = Math.Max(0, Mark.Gear - shot.Damage); shot.Life = 0; Ship.Events.Add(new("hit", Mark.Position, shot.Damage)); }
            if (hook && Near(Mark.Position, Mark.Gear < 12 ? 330 : 190))
            {
                if (Mark.Gear < 12) { Covert = false; Alarm++; BeginBoard(); return; }
                Queried = Mark; Phase = PrizePhase.Hail; Version++; return;
            }
        }
        alarmClock -= dt;
        if ((Phase == PrizePhase.Chase || Alarm > 1) && alarmClock <= 0)
        {
            alarmClock = Math.Max(6, 15 - Alarm);
            if (Ship.Enemies.Count < 3) Pursuer();
        }
        if (hook) ThrowLine();
    }
    bool Near(Vector2 at, float radius) => Vector2.DistanceSquared(Ship.Position, at) < radius * radius;
    void Pursuer()
    {
        var p = Water(Ship.Position + bearing * 310 + Wind * (random.Index(2) == 0 ? 340 : -340), 70);
        var foe = Ship.DropPatrol(random.Index(2) == 0 ? EnemyKind.Ray : EnemyKind.Serpent, p, 1.05f, false);
        if (foe != null) foe.Role = random.Index(2) == 0 ? PatrolRole.Flanker : PatrolRole.Mortar;
    }
    void ThrowLine()
    {
        float reach = Outfit == Loadout.Longline ? 650 : 490;
        var foe = Ship.Enemies.Where(e => e.Health > 0 && Near(e.Position, reach)).MinBy(e => Vector2.DistanceSquared(e.Position, Ship.Position));
        if (foe == null || lineClock > 0) return;
        HookEnd = foe.Position; HookFlash = .5f; lineClock = Math.Max(1.5f, 4.1f - Rigging * .4f); Ship.Grapple(foe);
    }
    public Vector2? Aim()
    {
        var foe = Ship.Enemies.Where(e => e.Health > 0 && Near(e.Position, 580)).MinBy(e => Vector2.DistanceSquared(e.Position, Ship.Position));
        if (Phase == PrizePhase.Chase && Near(Mark.Position, 650)) return Mark.Position;
        if (Phase == PrizePhase.Inquiry && Inquiry is { RivalOn: true } field && Near(field.Rival, 650)) return field.Rival;
        if (Phase == PrizePhase.Assize && Assize != null && Near(Assize.Quarter, 640)) return Assize.Quarter;
        return foe?.Position;
    }
    public void Hail(int choice)
    {
        if (Phase != PrizePhase.Hail || Queried == null) return;
        if (choice == 4) { Phase = PrizePhase.Search; Say("The watch boat sheers away to inspect another hull."); return; }
        if (Queried != Mark)
        {
            if (choice == 5) { Allies++; Purse += 2; Queried.Released = true; Ship.Patch(3); Say("A cleared boat flies your pennant. She’ll speak for you at the next anchorage."); }
            else { Alarm++; Pursuer(); Say("The stamp belongs to a civilian crew. The pilot asks questions about your colors."); }
            Phase = PrizePhase.Search; Cycle(); return;
        }
        if (choice == 5) { Phase = PrizePhase.Search; Say("The ship shows the exact stamped mark from the packet. Lio keeps her in sight."); return; }
        if (choice == CorrectCall && Report > 0)
        { Covert = true; QuietEntries++; Evidence++; BeginBoard(); return; }
        if (choice != 3) Alarm++;
        Phase = PrizePhase.Chase; Say("The prize turns away under full sail. Bring down the rigging with Vara’s gun.");
    }
    void BeginBoard() { HookEnd = Mark.Position; HookFlash = .5f; Ship.Velocity = Vector2.Zero; Phase = PrizePhase.Board; Version++; }
    public void Upgrade(int pick)
    {
        if (Ship.Mode != VoyageMode.Upgrade) return;
        if (pick < Ship.UpgradeChoices.Count) Ship.Upgrade(Ship.UpgradeChoices[pick]); else Ship.TakeUpgradeHeal();
        Version++;
    }
    public void FinishStage(bool won, int silver, float strength, bool freed = false)
    {
        if (!AtChild) return; Purse += Math.Max(0, silver);
        if (!won) { Lose("The watch returned with the silver already stowed."); return; }
        if (SettleCommission(Phase, strength)) return;
        if (Phase == PrizePhase.Board) { Strain = Math.Clamp((int)MathF.Round((1 - strength) * 48), 0, 45); if (freed) Prisoners++; else Evidence++; }
        if (Phase == PrizePhase.Landfall) { Strain = Math.Clamp((int)MathF.Round((1 - strength) * 45), 0, 44); Evidence += 2; Alarm = Math.Max(0, Alarm - 1); }
        if (Phase == PrizePhase.Crossing) { Ship.Health = Math.Max(1, Ship.MaxHealth * strength); Allies++; Kits++; }
        Purse += 4 + Index; Phase = PrizePhase.Refit; Version++;
    }
    public void Refit(int pick)
    {
        if (Phase != PrizePhase.Refit) return;
        if (pick == 0) { Ship.Patch(29); Strain = Math.Max(0, Strain - 17); Kits++; }
        else if (pick == 1) { Rigging++; Ship.ReloadRank++; Alarm++; }
        else { Allies++; Alarm = Math.Max(0, Alarm - 2); Evidence++; }
        if (++Index < Operations.Length) { BeginReach(); return; }
        Assize = new(this, Water, bearing, seed + Mark.Stamp); Phase = PrizePhase.Assize;
        Say("The marshal has called a floating assize. Win a public award or take the prize out of seizure.");
    }
    internal void TakePrize(Vector2 prize)
    {
        HasFinalTow = true; Tow = prize; lastTow = Ship.Position; returnWake.Enqueue(lastTow);
        Exit = Water(Ship.Position + bearing * 2350, 240);
        Gates = [Water(Vector2.Lerp(Ship.Position, Exit, .32f) + Wind * 240, 140), Water(Vector2.Lerp(Ship.Position, Exit, .69f) - Wind * 270, 140)];
        Ship.Enemies.Clear(); Phase = PrizePhase.Return; Version++; Say("The captives are aboard. Bring both hulls past the two pilot gates to the home tender.");
    }
    void Homeward(float dt, bool hook)
    {
        Tow = Trail(Ship, Tow, returnWake, ref lastTow, ref towPinned, dt, 108);
        if (homeGateGuard != ReturnGate && Near(Destination, 810))
        { homeGateGuard = ReturnGate; Pursuer(); if (Alarm > 2) Pursuer(); }
        if (Ship.Events.Any(e => e.Kind == "bossExplosion" && Vector2.Distance(e.Position, Tow) < e.Value)) TowHull -= 11;
        if (TowHull <= 0) { Lose("The prize founders in the roads. Both crews take to the open boats."); return; }
        if (Near(Destination, 192) && Vector2.Distance(Tow, Destination) < 505)
        {
            if (ReturnGate < Gates.Length) { ReturnGate++; Purse += 3; Ship.Xp += 5; Say("The pilot lowers her flag. Both hulls have made the gate."); }
            else if (hook) { Purse += 12 + Prisoners + Evidence; Phase = PrizePhase.Won; Version++; }
        }
        else if (hook) ThrowLine();
    }
    public void Withdraw() { if (Phase is not (PrizePhase.Won or PrizePhase.Lost)) Lose("The crew bring home the silver earned before withdrawing."); }
    void Lose(string line) { Phase = PrizePhase.Lost; Say(line); }
}
