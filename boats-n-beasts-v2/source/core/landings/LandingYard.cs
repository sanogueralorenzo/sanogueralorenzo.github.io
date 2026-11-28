using System.Numerics;

namespace BoatsNBeasts.Core;

public enum LandingJob { Weights, Nets, Mould, Escort, Capstans, Breakers }
public enum YardPhase { Fork, BranchFight, Work, Crossroads, GateFight, Camp, Guardian, Keys, Release, Departure, Lost }
public sealed partial class LandingYard
{
    public LandingPlan Plan { get; private set; } = null!;
    public Vector2 Camp => Plan.Campsite;
    public Vector2 Gate => Plan.Gate;
    public Vector2[] Locks => Plan.Locks;
    public Vector2 Ferry => Plan.Ferry;
    public readonly CampaignOrder Order;
    public readonly LandingRegion Region;
    public readonly Loadout Outfit;
    public readonly List<YardBeastState> Foes = [];
    public readonly List<YardAttack> Attacks = [];
    public readonly List<Vector2> SilverDrops = [];
    public readonly bool[] Completed = new bool[2];
    public readonly LandingJob[] Options = new LandingJob[2];
    public readonly int[] Sequence = [0, 1, 2];
    public readonly bool[] Secured = new bool[3];
    public Vector2 Player, Mate, Heading = -Vector2.UnitY;
    public Vector2 HookEnd, Billet, Passenger, KeyPlace;
    public YardPhase Phase { get; private set; } = YardPhase.Fork;
    public int BrokenBridge => Plan.BrokenBridge;
    public bool FoundStores { get; private set; }
    public bool SpentStores { get; private set; }
    public bool AtStores => FoundStores && !SpentStores && Vector2.DistanceSquared(Player, Plan.Pocket) < 2;
    public float HazardClock => Clock * .74f + District;
    public float HazardBeat => HazardClock - MathF.Floor(HazardClock / 5) * 5;
    public bool LiveHazard => District > 0 && Phase is not (YardPhase.Camp or YardPhase.Guardian or YardPhase.Keys or YardPhase.Release or YardPhase.Departure or YardPhase.Lost);
    public Vector2 HazardStart => Plan.Ledger + new Vector2(-1.7f, MathF.Sin(District) * .4f);
    public Vector2 HazardEnd => Plan.Ledger + new Vector2(1.7f, -MathF.Sin(District) * .4f);
    public Vector2 HazardPosition => Vector2.Lerp(HazardStart, HazardEnd, Math.Clamp((HazardBeat - 1.6f) / 1.15f, 0, 1));
    Vector2 footVelocity;
    public int District { get; private set; }
    public int Branch { get; private set; } = -1;
    public int Health { get; private set; }
    public int MaximumHealth { get; private set; }
    public int Silver { get; private set; }
    public int Chits { get; private set; }
    public int Edge { get; private set; }
    public int Quickline { get; private set; }
    public int Progress { get; private set; }
    public bool Carrying { get; private set; }
    public bool Anchored { get; private set; }
    public bool Intercept { get; private set; }
    public Vector2 Delivery => Plan.Summit + new Vector2(Branch == 0 ? -2.4f : 2.4f, 1.60f);
    public Vector2 ScaleSite => Plan.Ledger;
    public bool Repaired { get; private set; }
    public Vector2 RepairPost
    {
        get
        {
            if (BrokenBridge < 0) return Vector2.Zero;
            var span = Plan.Passages[BrokenBridge]; var left = Vector2.Lerp(span.From, span.To, .28f); var right = Vector2.Lerp(span.From, span.To, .72f);
            return Vector2.DistanceSquared(Player, left) < Vector2.DistanceSquared(Player, right) ? left : right;
        }
    }
    public int GuardCount { get; private set; }
    readonly LandingStep[] contract;
    public int FinalIndex { get; private set; }
    public LandingStep FinalStep => contract[Math.Min(FinalIndex, contract.Length - 1)];
    public bool Braced { get; private set; }
    public readonly bool[] GuardPins = new bool[2], HotPins = new bool[2];
    public bool Harness => GuardPins.Any(x => x);
    public bool ChargeHarness => Order.Id == "cinder-kiln" || Order.Id == "sable-dog";
    public string GuardFitting => Region.Climate switch
    {
        IslandClimate.Kiln => "yoke pin",
        IslandClimate.Orchard => "wing stay",
        IslandClimate.Delta => "press peg",
        IslandClimate.Shelf => "steam vent",
        IslandClimate.Loom => "warp spool",
        IslandClimate.Reef => "air valve",
        IslandClimate.Court => "bench pin",
        _ => "survey wire"
    };
    public bool Finishing => Phase is YardPhase.Keys or YardPhase.Release;
    public Vector2 FinalSite => FinalStep.Site switch
    {
        YardSite.West => Locks[0],
        YardSite.East => Locks[1],
        YardSite.Fallen => KeyPlace,
        YardSite.Crane => Gate,
        YardSite.Stairs => Plan.Summit + new Vector2(0, 2.3f),
        _ => Ferry
    };
    public Vector2 ReleaseLever => FinalSite + new Vector2(FinalSite.X > 0 ? -1.6f : 1.6f, .75f);
    public Vector2 DeliverTo => Plan.Summit + new Vector2(.65f, 2.25f);
    public float Clock, Swing, Hook, Dash, Hurt, HookWait, DodgeWait, LineClock;
    public string Line = "";
    public bool Boarded { get; private set; }
    public bool PassengerFree { get; private set; }
    public bool RescuedPassenger { get; private set; }
    public bool AtCamp => Vector2.Distance(Player, Camp) < 1.45f;
    public bool CanTrade => Phase == YardPhase.Camp && AtCamp;
    public int LegCount => Math.Max(1, Order.Legs);
    public LandingJob Job => Options[Math.Max(0, Branch)];
    public Vector2 Workbench => Plan.Bells[Math.Max(0, Branch)];
    public Vector2 Mould => Workbench + new Vector2(1.03f, .85f);
    public string DistrictName => Region.Districts[(District + DistrictOffset) % Region.Districts.Length];
    int DistrictOffset => Order.Island.Length == 0 ? 0 : Math.Abs(Order.Island.Sum(c => (int)c)) % Region.Districts.Length;
    public string Objective => Phase switch
    {
        YardPhase.Fork => "Choose a yard to enter",
        YardPhase.BranchFight => "Clear the work yard",
        YardPhase.Work => Job switch
        {
            LandingJob.Weights => Carrying ? "Weigh the stamp at the register" : $"Find {Region.Marks[Sequence[Math.Min(2, Progress)]]}  ·  {Progress}/3",
            LandingJob.Nets => Carrying ? "Carry the net to the upper crane" : $"Snag the drift lines  ·  {Progress}/3",
            LandingJob.Mould => Carrying ? "Deliver the cast piece to the upper slip" : $"Drive the {Region.Pin} into its seat",
            LandingJob.Escort => PassengerFree ? "Lead the worker to the marked steps" : $"Free the {Region.Castaway}",
            LandingJob.Capstans => Anchored ? $"Turn the {Region.Marks[Sequence[Math.Min(2, Progress)]]} winch" : "Catch the central cable with Lio’s hook",
            _ => $"Break the guard seals  ·  {Progress}/3"
        },
        YardPhase.Crossroads => "Take the upper gate or work the other yard",
        YardPhase.GateFight => "Open the toll gate",
        YardPhase.Camp => District + 1 < LegCount ? "Trade or take the north ferry" : "Trade or open the last gate",
        YardPhase.Guardian => Harness ? (ChargeHarness ? "Lure a charge through each gold pin" : "Unfasten the two marked " + GuardFitting + "s") : $"Break {Order.Boss}’s guard",
        YardPhase.Keys or YardPhase.Release => FinalStep.Instruction,
        YardPhase.Departure => "Board with your crew",
        _ => "The crew rows for home"
    };
    readonly int seed;
    readonly GuardianForm breed;
    readonly int flourish;
    Random rand = null!;
    Vector2 dashDirection, billetVelocity, lastTrail;
    readonly Queue<Vector2> trail = [];
    float swingDelay, safe;
    bool fed;
    public LandingYard(CampaignOrder order, int seed, int stores, Loadout outfit = Loadout.Standard)
    {
        Order = order; Outfit = outfit; breed = order.Island.Length > 0 ? GuardianBreed.Named(order.Boss) : GuardianForm.Regional; flourish = order.Id.Sum(c => c) % 3; Region = LandingRegion.From(order.Region); contract = LandingContract.For(order); this.seed = seed;
        MaximumHealth = Health = 8 + Math.Clamp(stores, 0, 2) * 2 + (Outfit == Loadout.Lifeboat ? 4 : 0); GenerateDistrict();
    }
    void GenerateDistrict()
    {
        uint orderKey = 2166136261;
        foreach (char letter in Order.Id) orderKey = unchecked((orderKey ^ letter) * 16777619);
        rand = new(unchecked((int)SeedRandom.Hash((uint)seed, District, Order.Tier, orderKey)));
        var start = (int)Region.Climate + District * 2 + (int)(orderKey % 6);
        Options[0] = (LandingJob)((start + rand.Next(2)) % 6);
        Options[1] = (LandingJob)(((int)Options[0] + 1 + rand.Next(4)) % 6);
        rand.Shuffle(Sequence);
        Plan = new(Order, District, seed); Repaired = FoundStores = SpentStores = false; footVelocity = Vector2.Zero;
        Player = Plan.Dock; Mate = Player + new Vector2(.25f, -.5f);
        Branch = -1; Phase = YardPhase.Fork; fed = false;
        Array.Clear(Completed); Foes.Clear(); Attacks.Clear(); SilverDrops.Clear(); ClearJob();
        Say(District == 0 ? Order.Brief : "Vara opens the route book at " + DistrictName + ". The ferryman will take fresh work chits.");
    }
    void Say(string line) { Line = line; LineClock = 6; }
    void ClearJob()
    {
        Progress = 0; PassengerFree = Carrying = Anchored = Intercept = false; trail.Clear(); Array.Clear(Secured); billetVelocity = Vector2.Zero;
    }
    void Pick(int side)
    {
        Branch = side; ClearJob(); Phase = YardPhase.BranchFight;
        SpawnWatch(Workbench, false);
        Say(side == 0 ? "Lio takes the outer line. Cut across their swing when the painted ground clears." : "Vara climbs onto the rail. She points out the gaps in the toll guard.");
    }
    public void Interact()
    {
        if (!SpentStores && Near(Plan.Pocket, 1.4f))
        {
            FoundStores = true; Say("A cache under the signal rag. Take the field ration with 1 or the trade chits with 2."); return;
        }
        int side = Array.FindIndex(Plan.Bells, p => Vector2.Distance(Player, p) < 1.30f);
        if (Phase is YardPhase.Fork or YardPhase.Crossroads && side >= 0 && !Completed[side]) { Pick(side); return; }
        if (Phase == YardPhase.Crossroads && Near(Gate, 1.55f))
        {
            Phase = YardPhase.GateFight; SpawnWatch(Plan.Summit, true);
            Say("The watch has the release lever. Clear the head of the slip."); return;
        }
        if (Phase == YardPhase.Camp && Near(Gate, 1.55f))
        {
            if (District + 1 < LegCount) { District++; GenerateDistrict(); return; }
            Phase = YardPhase.Guardian; Branch = -1;
            int hp = 122 + Math.Min(3, Order.Tier / 2) * 11;
            Foes.Add(new(Plan.Summit + new Vector2(0, -.40f), YardBeast.Guardian, hp) { Wait = 1.4f });
            Say(Order.Boss + " blocks the upper yard. Hook at the wind-up. Strike when the guard drops."); return;
        }
        if (Finishing)
        {
            if (FinalStep.Action == LandingAction.Turn && Near(FinalSite, 1.24f)) AdvanceFinal();
            else if (FinalStep.Action == LandingAction.Brace && Braced && Near(ReleaseLever, 1.14f)) AdvanceFinal();
            else if (FinalStep.Action == LandingAction.Guide && !PassengerFree && Near(Passenger, 1.18f))
            { PassengerFree = true; lastTrail = Player; trail.Enqueue(Player); Say("Stay together. Lead them out to the marked steps."); }
            return;
        }
        if (Phase == YardPhase.Departure && Near(Ferry, 1.55f)) { Boarded = true; return; }
        if (Phase != YardPhase.Work) return;
        if (Carrying)
        {
            var delivery = Job == LandingJob.Weights ? ScaleSite : Delivery;
            if (!Near(delivery, 1.25f)) { Say("The marked receiver is waiting for the load."); return; }
            Carrying = false;
            if (Job == LandingJob.Weights) { Secured[Sequence[Progress]] = true; JobStep(); }
            else CompleteJob();
            return;
        }
        if (Job is LandingJob.Weights or LandingJob.Capstans)
        {
            for (int i = 0; i < 3; i++)
                if (Near(Mark(i), .94f))
                {
                    if (i == Sequence[Progress] && Job == LandingJob.Weights) { Carrying = true; Say("That's the stamped load. Carry it to the brass scale at the register."); }
                    else if (i == Sequence[Progress] && Anchored) { Anchored = false; Secured[i] = true; JobStep(); }
                    else if (i == Sequence[Progress]) Say("Lio must catch the cable with K before you turn the winch.");
                    else Say("The mark in the register is " + Region.Marks[Sequence[Progress]] + ".");
                    return;
                }
        }
        else if (Job == LandingJob.Escort && !PassengerFree && Near(Passenger, 1.18f))
        {
            PassengerFree = true; lastTrail = Player; trail.Enqueue(Player);
            Say("Stay close. The painted steps overlook the freight lock.");
        }
        else if (Job == LandingJob.Mould && !Carrying && Near(Workbench, 1.1f))
        { Billet = Workbench + new Vector2(-.9f, -.40f); billetVelocity = Vector2.Zero; Say("Pin back on the block. Knock it toward the striped seat."); }
    }
    bool Near(Vector2 p, float range) => Vector2.DistanceSquared(Player, p) < range * range;
    public void Trade(int slot)
    {
        if (AtStores)
        {
            if (slot is not (1 or 2)) return;
            SpentStores = true;
            if (slot == 1) { Health = Math.Min(MaximumHealth, Health + 3); Say("The cache holds a fresh water flask and a dry biscuit."); }
            else { Chits += 2; Say("Two unused work chits. The stamp is still good at the upper slip."); }
            return;
        }
        if (!CanTrade) return;
        int cost = slot == 1 ? 1 : slot == 4 ? 4 : 2;
        if (Chits < cost) { Say($"The trader asks {cost} work chits."); return; }
        switch (slot)
        {
            case 1:
                if (fed || Health == MaximumHealth) { Say("The ration tin is full."); return; }
                fed = true; Health = Math.Min(MaximumHealth, Health + 5); break;
            case 2:
                if (Edge >= 3) { Say("The edge is as fine as it goes."); return; }
                Edge++; break;
            case 3:
                if (Quickline >= 3) { Say("The reel is already fully wound."); return; }
                Quickline++; break;
            case 4:
                if (District + 2 >= LegCount) { Say("The shortcut ends before the final gate."); return; }
                Chits -= cost; District += 2; GenerateDistrict(); Say("The ash tender takes your chits and poles straight past one district."); return;
            default: return;
        }
        Chits -= cost;
        Say(slot == 1 ? "Vara divides the hot ration three ways." : slot == 2 ? "Vara fits the tempered edge." : "Lio takes three turns out of his line.");
    }
    public Vector2 Walkable(Vector2 point) => Plan.Walkable(point);
    public Vector2 WeightAt(int i)
    {
        float angle = Clock * 1.3f + i * MathF.PI;
        return Workbench + new Vector2(MathF.Cos(angle) * 1.70f, MathF.Sin(angle) * 1.20f);
    }
    public Vector2 PassengerDock => Plan.LandingSteps;
    public void Tick(float dt, Vector2 direction, bool cut, bool dodge, bool hook)
    {
        if (Boarded || Phase == YardPhase.Lost) return;
        Clock += dt;
        Swing = Decay(Swing, dt); Hook = Decay(Hook, dt); Dash = Decay(Dash, dt); Hurt = Decay(Hurt, dt);
        HookWait = Decay(HookWait, dt); DodgeWait = Decay(DodgeWait, dt); safe = Decay(safe, dt); swingDelay = Decay(swingDelay, dt);
        LineClock = Decay(LineClock, dt);
        if (direction.LengthSquared() > 1) direction = Vector2.Normalize(direction);
        if (direction.LengthSquared() > .01f) Heading = direction;
        if (dodge && DodgeWait == 0) { dashDirection = Unit(Heading); Dash = .22f; DodgeWait = Outfit == Loadout.Broadside ? 1.55f : 1.05f; safe = .28f; }
        var desired = direction * (Carrying ? 2.35f : 2.85f);
        footVelocity = Plan.Terrain == YardTerrain.IceLead ? Vector2.Lerp(footVelocity, desired, Math.Min(1, dt * 6)) : desired;
        Player = Walkable(Player + (Dash > 0 ? dashDirection * 8.6f : footVelocity) * dt);
        if (LiveHazard && HazardBeat >= 1.60f && HazardBeat <= 2.75f && Near(HazardPosition, .52f) && safe == 0) Damage(1);
        Mate = Walkable(Vector2.Lerp(Mate, Player - Heading * .67f + new Vector2(.22f, -.18f), Math.Min(1, dt * 4.6f)));
        bool slashing = cut && swingDelay == 0 && Dash == 0, hooking = hook && HookWait == 0;
        if (hooking && !Repaired && BrokenBridge >= 0 && Near(RepairPost, 1.1f) && Chits > 0)
        {
            Chits--; Repaired = true; Hook = .5f; HookWait = 1; HookEnd = RepairPost; Plan.Splice();
            hooking = false; Say("The spare line holds. Both crews can cross the repaired bridge.");
        }
        bool usedHook = Finishing ? FinishWork(dt, slashing, hooking) : Phase == YardPhase.Work && Work(dt, slashing, hooking);
        var nearest = Foes.MinBy(f => Vector2.DistanceSquared(f.Position, Player));
        if (slashing)
        {
            Swing = .23f; swingDelay = .42f;
            if (nearest != null && Near(nearest.Position, 1.85f)) Heading = Unit(nearest.Position - Player);
            foreach (var enemy in Foes)
            {
                var to = enemy.Position - Player;
                if (to.Length() > (enemy.Kind == YardBeast.Guardian ? 1.75f : 1.36f) || Vector2.Dot(Unit(to), Unit(Heading)) < -.12f) continue;
                bool shield = enemy.Kind == YardBeast.Porter || enemy.Kind == YardBeast.Guardian;
                bool guarded = shield && enemy.Stagger == 0 && Vector2.Dot(enemy.Heading, -Unit(to)) > .46f;
                bool covered = Foes.Any(f => f != enemy && f.Kind == YardBeast.Porter && f.Stagger == 0 && Vector2.DistanceSquared(f.Position, enemy.Position) < 2.25f);
                int blade = Outfit == Loadout.Broadside ? 3 : Outfit == Loadout.Longline ? -1 : 0;
                if (enemy.Kind == YardBeast.Guardian && Harness) continue;
                enemy.Health -= Math.Max(1, (guarded || covered ? 2 : enemy.Stagger > 0 ? 10 : 6) + Edge * 2 + blade);
                enemy.Hit = .18f;
            }
        }
        if (Phase == YardPhase.Guardian && Harness)
        {
            for (int i = 0; i < 2; i++)
            {
                if (!GuardPins[i]) continue;
                if (ChargeHarness)
                {
                    if (HotPins[i] && slashing && Near(Locks[i], 1.28f)) { GuardPins[i] = false; Say("The hot bolt splits. The harness slips to one side."); }
                }
                else if (i == 0 && hooking && Near(Locks[i], 2.70f))
                { GuardPins[i] = false; usedHook = true; Hook = .52f; HookEnd = Locks[i]; HookWait = 1.1f; Say("The first fitting is free. Break the other with your blade."); }
                else if (i == 1 && slashing && Near(Locks[i], 1.25f)) GuardPins[i] = false;
            }
            if (!Harness) Say("The harness is gone. The crew can reach the exposed seam.");
        }
        if (hooking && !usedHook && nearest != null && Vector2.Distance(Mate, nearest.Position) < (Outfit == Loadout.Longline ? 5.3f : 4.0f))
        {
            bool caught = Attacks.RemoveAll(a => a.Source == nearest && !a.Fired && !(Harness && ChargeHarness)) > 0;
            Hook = .42f; HookWait = 5.1f - Quickline * .85f + (Outfit == Loadout.Longline ? -1 : Outfit == Loadout.Lifeboat ? 1 : 0); HookEnd = nearest.Position;
            if (nearest.Kind != YardBeast.Guardian || !Harness) nearest.Health -= caught ? 12 : 3; nearest.Stagger = caught ? 1.35f : .45f;
            nearest.Rush = 0; nearest.Wait = .5f; nearest.Hit = .16f;
            if (caught) Say("Lio has the line. Strike the exposed seam!");
        }
        for (int i = Foes.Count - 1; i >= 0; i--)
        {
            var beast = Foes[i];
            if (beast.Health <= 0)
            {
                int count = beast.Kind == YardBeast.Guardian ? 6 : 2;
                for (int k = 0; k < count; k++)
                {
                    float a = k * MathF.Tau / count;
                    SilverDrops.Add(Walkable(beast.Position + new Vector2(MathF.Cos(a), MathF.Sin(a)) * .41f));
                }
                Attacks.RemoveAll(a => a.Source == beast);
                Foes.RemoveAt(i);
                if (beast.Kind == YardBeast.Guardian)
                {
                    Phase = YardPhase.Keys; KeyPlace = beast.Position; BeginFinal();
                }
                else if (Foes.Count == 0 && Phase == YardPhase.BranchFight) BeginJob();
                else if (Foes.Count == 0 && Phase == YardPhase.GateFight)
                {
                    Phase = YardPhase.Camp; Chits++; Say("The slip is ours. At the striped tarp, trade chits for rations, an edge or a faster reel.");
                }
                continue;
            }
            BeastTurn(beast, dt);
        }
        for (int i = Attacks.Count - 1; i >= 0; i--)
        {
            var a = Attacks[i]; a.Age += dt;
            if (a.Age >= a.Lead && !a.Fired)
            {
                a.Fired = true;
                if (Harness && ChargeHarness && a.Shape == AttackShape.Lane && a.Source.Kind == YardBeast.Guardian)
                    for (int pin = 0; pin < 2; pin++) if (GuardPins[pin] && a.Contains(Locks[pin])) { HotPins[pin] = true; Say("The charge drove a pin red-hot. Cut it with J."); }
                if (a.Rush) { a.Source.Rush = .42f; a.Source.RushTo = Walkable(a.Target); }
            }
            if (a.Fired && !a.Hurt && a.Contains(Player) && safe == 0) { Damage(a.Source.Kind == YardBeast.Guardian ? 2 : 1); a.Hurt = true; }
            if (a.Age >= a.Lead + a.Active) Attacks.RemoveAt(i);
        }
        for (int i = SilverDrops.Count - 1; i >= 0; i--) if (Near(SilverDrops[i], .90f)) { SilverDrops.RemoveAt(i); Silver++; }
        if (Health <= 0) { Phase = YardPhase.Lost; Say("Lio cuts the line. The crew gets you clear with the silver."); }
    }
    void Damage(int count) { Health = Math.Max(0, Health - count); safe = .90f; Hurt = .22f; }
    static float Decay(float v, float dt) => Math.Max(0, v - dt);
    static Vector2 Unit(Vector2 v) => v.LengthSquared() > .0001f ? Vector2.Normalize(v) : Vector2.UnitY;
}
