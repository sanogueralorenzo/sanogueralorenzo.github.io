using System.Numerics;

namespace BoatsNBeasts.Core;

public enum FleetField { Muster, Rescue, Refit, Passage, Captain, Refuge, Won, Lost }
public enum FleetRole { Tender, Tug, Sloop }
public enum FleetTask { Rescue, Brace, Signal, Ferry, Cut, Board, Rally }
public enum FleetStrike { Mortar, Shear, Nets, Echo, Charge, Ice, Swarm, Squall }

public sealed class CommandHull(FleetRole role, string name, string skipper, Vector2 at, float maximum, float condition)
{
    public FleetRole Role { get; } = role;
    public string Name { get; } = name;
    public string Skipper { get; } = skipper;
    public float Maximum { get; } = maximum;
    public float Hull { get; internal set; } = Math.Max(1, maximum * condition);
    public Vector2 Position = at, Bow = -Vector2.UnitY;
    public int Assignment = -1, People;
    public float Progress, Guard, Cooldown, Hit, Signals;
    internal float Pinned;
    internal Vector2 LastLead = at;
    internal readonly Queue<Vector2> Bends = [];
    internal readonly Queue<Vector2> HomeWake = [];
    public bool Afloat => Hull > 0;
}
public sealed class FleetPost(FleetTask task, string title, Vector2 position, Vector2 berth, int stock = 0)
{
    public FleetTask Task { get; } = task;
    public string Title { get; } = title;
    public Vector2 Position = position, Berth = berth;
    public int Stock = stock;
    public float Work;
    public int Gate;
    public bool AtFork;
    public bool Done;
}
public sealed class FleetLane(FleetStrike strike, Vector2 from, Vector2 to, float width, float warning)
{
    public FleetStrike Strike { get; } = strike;
    public Vector2 From = from, To = to;
    public float Width = width, Warning = warning, Live;
    public bool Fired;
    internal readonly HashSet<int> Hit = [];
}
public sealed partial class FleetCommand
{
    public CampaignOrder Order { get; }
    public SeaCountry Country { get; }
    public Voyage Ship { get; }
    public CommandHull[] Allies { get; }
    public List<FleetPost> Stations { get; } = [];
    public List<FleetLane> Lanes { get; } = [];
    public FleetField Field { get; private set; } = FleetField.Muster;
    public int Selected { get; private set; }
    public int Post { get; private set; }
    public int Silver { get; private set; }
    public int Kits { get; private set; }
    public int Rescued { get; private set; }
    public int PickedUp => Allies.Sum(a => a.People);
    public int Delivered { get; private set; }
    public int GunsDown { get; private set; }
    public int HullsAfloat => Allies.Count(a => a.Afloat);
    public bool Won => Field == FleetField.Won;
    public bool Lost => Field == FleetField.Lost;
    public bool AtSea => Field is FleetField.Rescue or FleetField.Passage or FleetField.Captain or FleetField.Refuge;
    public float Condition => Math.Clamp(.34f * Ship.Health / Ship.MaxHealth + .66f * Allies.Average(a => a.Hull / a.Maximum), 0, 1);
    public string Call { get; private set; } = "";
    public string Cargo { get; }
    public string Signal { get; }
    public string Haven { get; }
    public Vector2 Refuge { get; private set; }
    public Vector2 EnemyHull { get; private set; }
    public Vector2 EnemyBow { get; private set; } = -Vector2.UnitY;
    public float EnemyStrength { get; private set; }
    public float Breach { get; private set; }
    public bool EnemyVisible => Field == FleetField.Captain;
    public float Clock { get; private set; }
    public FleetField NextField { get; private set; }
    public Vector2 Center { get; private set; }
    public string Objective => Field switch
    {
        FleetField.Rescue => $"Bring three people to the hospital tender  ·  {Rescued}/3 safe",
        FleetField.Passage => $"Tow both {Cargo} lighters to their matching gates  ·  {Delivered}/2",
        FleetField.Captain when GunsDown < 2 => $"Silence both command stations  ·  {GunsDown}/2",
        FleetField.Captain when Sightings < 2 => $"Identify the fleeing flagship  ·  {Sightings}/2 bearings",
        FleetField.Captain => EnemyStrength > 0 ? $"Disable the identified rig of {Order.Boss}  ·  {EnemyStrength:0}" : $"Send a boarding hull and take the colors of {Order.Boss}",
        FleetField.Refuge => $"Meet the flotilla at {Haven}. Q signs the crews home.",
        _ => Order.Objective
    };
    public Vector2 Destination => Field == FleetField.Refuge && HomeGate == 2 ? Refuge : Stations.Count > 0 ? Stations[Post].Position : Ship.Position;
    public string TaskName => Field == FleetField.Refuge ? (HomeGate == 2 ? Haven : HomeGate == 0 ? "Outer company flag" : "Consort chain") : Stations.Count > 0 ? Stations[Post].Title : "Muster";
    readonly Vector2 heading, side;
    readonly int variant;
    readonly Loadout outfit;
    readonly OceanWorld pilot;
    SeedRandom random;
    float nextThreat, nextBeast, patchWait;
    int fieldNo, salvos, repairs, reinforced;
    public FleetCommand(CampaignOrder order, int seed, int stores = 0, Loadout outfit = Loadout.Standard, BoatKind vessel = BoatKind.Cutter, float startingCondition = 1)
    {
        Order = order; Country = SeaCountry.At(order.Region, order.Island); this.outfit = outfit;
        uint hash = 17; foreach (char ch in order.Id) hash = unchecked(hash * 31 + ch);
        random = new((uint)seed ^ hash); variant = (int)(hash % 4);
        float a = random.Range(0, MathF.Tau); heading = new(MathF.Cos(a), MathF.Sin(a)); side = new(-heading.Y, heading.X);
        var strength = Math.Clamp(startingCondition, .08f, 1);
        Ship = new((uint)seed, vessel, 1) { Charted = true, HullRank = Math.Clamp(stores, 0, 2), BroadsideRig = outfit == Loadout.Broadside };
        Ship.Weapons[0] = Math.Max(1, Ship.Weapons[0]); Ship.Health = Ship.MaxHealth * strength;
        pilot = new(Ship.World.Seed); Center = Water(new(18400 + order.Tier * 1600, -21000 - (hash % 7) * 2300), 250); Ship.Position = Center; Ship.World.Stream(Center);
        var islanders = FarLedger.Arcs.FirstOrDefault(a => a.Region == order.Region)?.Islands ?? [];
        var skippers = islanders.Select(i => i.Speaker.Split(',')[0]).ToArray();
        string Name(int index, string alt) => index < skippers.Length ? skippers[index] : alt;
        var articles = order.Articles;
        Cargo = articles?.Cargo ?? "relief"; Signal = articles?.Signal ?? "the double lantern"; Haven = articles?.Refuge ?? Country.Anchorage;
        Allies = [new(FleetRole.Tender,articles?.Vessel??"Good Measure",articles?.Captain??Name(0,"Ena"),At(-155,-290),80,strength),
            new(FleetRole.Tug,articles?.ConsortVessel??"Broad Back",articles?.Consort??Name(1,"Rill"),At(-205,245),142,strength),
            new(FleetRole.Sloop,"Reply All",Name(2,"Fenn"),At(-451,-35),97,strength)];
        Kits = 2 + Math.Clamp(stores, 0, 2) + (outfit == Loadout.Lifeboat ? 1 : 0);
    }
    Vector2 At(float forward, float port, float radius = 88) => Water(Center + heading * forward + side * port, radius);
    Vector2 Water(Vector2 near, float radius)
    {
        pilot.Stream(near);
        for (int circle = 0; circle <= 18; circle++)
            for (int i = 0; i < (circle == 0 ? 1 : 16); i++)
            {
                float a = i * MathF.Tau / 16 + circle * .28f;
                var p = near + new Vector2(MathF.Cos(a), MathF.Sin(a)) * circle * 62;
                if (pilot.IsWater(p, radius)) return p;
            }
        return Ship.Position;
    }
    public void Launch() { if (Field == FleetField.Muster) Open(FleetField.Rescue); }
    public void Refit(int choice)
    {
        if (Field != FleetField.Refit) return;
        if (choice == 0) { foreach (var a in Allies.Where(a => a.Afloat)) a.Hull = Math.Min(a.Maximum, a.Hull + 15); Ship.Patch(19); Kits++; }
        else if (choice == 1) { reinforced++; foreach (var a in Allies.Where(a => a.Afloat)) a.Guard = 5; }
        else { repairs++; Ship.ReloadRank = Math.Min(5, Ship.ReloadRank + 1); }
        Open(NextField);
    }
    public void Select(int index) { if (index >= 0 && index < Allies.Length) Selected = index; }
    public void SelectPost(int index) { if (index >= 0 && index < Stations.Count) Post = index; }
    public void Cycle() { if (Stations.Count > 0) Post = (Post + 1) % Stations.Count; }
    public void Recall()
    {
        if (!AtSea) return;
        var ally = Allies[Selected]; if (!ally.Afloat) return;
        Assign(ally, -1); Say(ally.Skipper + " acknowledges. Returning to the cutter.");
    }
    public void Dispatch()
    {
        if (!AtSea) return;
        if (Pilot != null) { Pilot.Cover(); return; }
        if (Field == FleetField.Refuge) { Acknowledge(); return; }
        var ally = Allies[Selected];
        if (!ally.Afloat) { SalvageAlly(ally); return; }
        if (Stations.Count == 0) return;
        if (Stations[Post].Done) { Say("That post is clear. Tab for another bearing."); return; }
        Assign(ally, Post); Say($"{ally.Skipper} takes {ally.Name} to {Stations[Post].Title}.");
    }
    public bool Patch()
    {
        if (!AtSea || Kits <= 0 || patchWait > 0) return false;
        if (Pilot != null) { if (!Pilot.Mend()) return false; Kits--; patchWait = 3; return true; }
        var ally = Allies[Selected]; bool close = Vector2.DistanceSquared(Ship.Position, ally.Position) < 340 * 340;
        if (close && ally.Hull < ally.Maximum && Ship.Health > Ship.MaxHealth * .35f)
        {
            if (!ally.Afloat) return SalvageAlly(ally);
            ally.Hull = Math.Min(ally.Maximum, ally.Hull + (outfit == Loadout.Lifeboat ? 61 : 43));
        }
        else if (Ship.Health < Ship.MaxHealth) Ship.Patch(outfit == Loadout.Lifeboat ? 52 : 34);
        else { return false; }
        Kits--; patchWait = 2; Say("The carpenters make fast with fresh canvas."); return true;
    }
    bool SalvageAlly(CommandHull ally)
    {
        if (Kits <= 0 || Vector2.DistanceSquared(Ship.Position, ally.Position) > 230 * 230) { Say("Bring a repair kit alongside the disabled vessel."); return false; }
        Kits--; ally.Hull = ally.Maximum * .43f; Assign(ally, -1); patchWait = 2; Say($"{ally.Skipper} reports water under the keel again."); return true;
    }
    public bool CallShipmate(Shipmate mate)
    {
        if (!AtSea) return false;
        if (Pilot != null) return Pilot.CallShipmate(mate);
        if (mate == Shipmate.Vara && Allies[Selected] is { Afloat: true } a && a.Hull < a.Maximum)
        { a.Hull = Math.Min(a.Maximum, a.Hull + 38); Say("Vara sends a crew and fresh oakum across."); return true; }
        return Ship.CallShipmate(mate);
    }
    public void Acknowledge()
    {
        if (Field != FleetField.Refuge) return;
        if (HomeGate < 2) { Hands(); return; }
        if (Vector2.Distance(Ship.Position, Refuge) > 190) { Say("Bring the cutter to the refuge pennant."); return; }
        if (Allies.Any(a => a.Afloat && Vector2.Distance(a.Position, Refuge) > 425)) { Say("The refuge keeper is counting hulls. The remaining ships are still making the gate."); return; }
        Silver += 7 + HullsAfloat * 3 + Rescued; Field = FleetField.Won; Say(Order.Homecoming);
    }
    void Assign(CommandHull a, int post) { if (a.Assignment != post) { a.Assignment = post; a.Progress = 0; a.Bends.Clear(); a.Pinned = 0; } }
    void Say(string message) { Call = message; }
    void Open(FleetField field)
    {
        Field = field; fieldNo++; Center = Water(Ship.Position + heading * (fieldNo == 1 ? 75 : 350), 190);
        Stations.Clear(); Lanes.Clear(); Ship.Shots.RemoveAll(s => s.Hostile);
        foreach (var ally in Allies) Assign(ally, -1);
        Post = 0; nextThreat = 2.1f; nextBeast = 5.8f; salvos = 0;
        if (field == FleetField.Rescue)
        {
            Refuge = At(-325, -412, 135);
            Stations.Add(new(FleetTask.Rescue, "Displaced ferry", At(685, -320), Refuge, 2));
            Stations.Add(new(FleetTask.Rescue, "Broken cabin", At(375, 535), Refuge, 2));
            Stations.Add(new(FleetTask.Brace, "Hospital screen", At(285, 85), Refuge));
            Stations.Add(new(FleetTask.Signal, "Pilots’ mast", At(480, -40), Refuge));
            Say("Two boats are breaking apart. Send ships to bring people to the hospital. The tug can shelter the crossing.");
        }
        else if (field == FleetField.Passage)
        {
            Stations.Add(new(FleetTask.Ferry, "Western lighter", At(280, -355), At(1120, -155), 1));
            Stations.Add(new(FleetTask.Ferry, "Eastern lighter", At(120, 405), At(1030, 395), 1));
            Stations.Add(new(FleetTask.Signal, Signal, At(680, 180), Center));
            Stations.Add(new(FleetTask.Brace, "The narrow water", At(635, -90), Center));
            Say("Both lighters must reach their own pilot gates. A signal ship can scatter the pickets while a tug takes the heavier berth.");
        }
        else if (field == FleetField.Captain)
        {
            EnemyHull = At(740, 95); EnemyStrength = 65 + Math.Min(Order.Tier, 8) * 2;
            Stations.Add(new(FleetTask.Cut, FirstDevice, At(400, -370), Center));
            Stations.Add(new(FleetTask.Cut, SecondDevice, At(945, 220), Center));
            Stations.Add(new(FleetTask.Signal, Signal, At(345, 330), Center));
            Stations.Add(new(FleetTask.Brace, "Refuge guard", At(540, -40), Center));
            Say($"{Order.Boss} holds the fairway. Put crews on both devices. A signal raises a clear shot for the cutter.");
        }
        else
        {
            Refuge = At(770, -115, 155);
            Stations.Add(new(FleetTask.Rally, Haven, Refuge, Refuge));
            foreach (var ally in Allies)
            {
                Assign(ally, 0); ally.HomeWake.Clear(); ally.HomeWake.Enqueue(Ship.Position); ally.LastLead = Ship.Position;
            }
            Say("The enemy strikes its colors. Bring the flotilla to the refuge and acknowledge the names ashore.");
        }
        PrepareHands(field);
    }
    void CloseField(FleetField next)
    {
        Silver += 4 + HullsAfloat; NextField = next;
        if (next == FleetField.Refuge) Open(next);
        else { Field = FleetField.Refit; Say("Both watches meet in sheltered water to choose the next fitting."); }
    }
    public Vector2? Aim()
    {
        if (Field == FleetField.Captain)
        {
            if (GunsDown >= 2 && NamedSignal && Vector2.Distance(Ship.Position, EnemyHull) < 700) return EnemyHull;
            if (Stations[Post] is { Task: FleetTask.Cut, Done: false } s && Vector2.Distance(Ship.Position, s.Position) < 640) return s.Position;
        }
        return Ship.Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(e.Position, Ship.Position) < 650 * 650)
            .MinBy(e => Vector2.DistanceSquared(e.Position, Ship.Position))?.Position;
    }
    public void Tick(float dt, SailInput input)
    {
        if (!AtSea) return;
        dt = Math.Clamp(dt, 0, .05f); Clock += dt; patchWait -= dt; handCooldown -= dt;
        if (Pilot != null) { WatchPilot(dt, input); return; }
        var prior = Ship.SilverEarned;
        Ship.Tick(dt, input);
        if (Ship.Mode == VoyageMode.Upgrade)
        {
            int fit = Ship.UpgradeChoices.FirstOrDefault(i => i == 0 || i == 8, -1);
            if (fit < 0) Ship.TakeUpgradeHeal(); else Ship.Upgrade(fit);
        }
        Silver += Ship.SilverEarned - prior;
        foreach (var ally in Allies) MoveAlly(ally, dt);
        if (Field != FleetField.Refuge || HomeGate < 2) Threats(dt);
        if (Field == FleetField.Captain) Commander(dt);
        if (Ship.Health <= 0 || HullsAfloat == 0) { Field = FleetField.Lost; Say("The surviving crews take to the refuge boats with the silver already aboard."); return; }

    }
}
