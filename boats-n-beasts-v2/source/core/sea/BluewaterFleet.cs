using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed record FleetAction(string Tender, string Picket, string Road, string Arsenal, string Signal, PatrolRole Screen)
{
    public static FleetAction? For(string id) => id switch
    {
        "cinder-float" => new("Sima’s quenching raft", "clinker monitor", "the cooling channel", "the clinker magazine", "quenching water", PatrolRole.Mortar),
        "reed-flute" => new("Pell’s fish barge", "mill-tax lugger", "the moving weir", "the sluice wheel", "sluice keys", PatrolRole.Flanker),
        "pear-winter" => new("Ilo’s wick tender", "lantern trawler", "the lantern bower", "the wax pump", "moth lanterns", PatrolRole.Caller),
        "ice-sled" => new("Anet’s stove boat", "frost mail clipper", "the steam lead", "the ice drill", "steam hammers", PatrolRole.Mortar),
        "loom-fleet" => new("the stitchers’ launch", "canvas shear", "the shroud race", "the wind capstan", "a storm spinnaker", PatrolRole.Flanker),
        "choir-air" => new("Oren’s breathing raft", "listening cutter", "the quiet reach", "the echo bell", "a muffling sail", PatrolRole.Caller),
        "sable-race" => new("the jurors’ skiff", "black-writ launch", "the witness channel", "the arrest lamp", "appeal pennants", PatrolRole.Mortar),
        "north-tow" => new("the mitten pilot", "blank-chart patrol", "the broken compass rose", "the star spindle", "eight harbor flags", PatrolRole.Flanker),
        "wake-salt-feet" => new("Uma’s cutting boat","salt-tax pinnace","the lower pans","the brine lift","root blankets",PatrolRole.Caller),
        "wake-bottle-school" => new("Cella’s diving tender","cork cutter","the root nursery","the pressure still","breathing bottles",PatrolRole.Flanker),
        "wake-wax-high" => new("the dispatch basket","wax seal cutter","the upper road","the courier perch","a double-route pennant",PatrolRole.Flanker),
        "wake-rise-together" => new("Latt’s ward lighter","fixed-bed monitor","the waking ground","the last mooring drum","the ward bell",PatrolRole.Mortar),
        "wake-tin-rise" => new("Islet’s diving boat","tin trawler","the moonward lift","the gravity winch","a moon counterweight",PatrolRole.Mortar),
        "wake-drum-space" => new("the listening raft","the downbeat launch","the silent beat","the drumhead brake","a palm drum",PatrolRole.Caller),
        "wake-pitch-release" => new("Toma’s chain bridge","tar-sheathed tender","the anchor spread","the main capstan","release irons",PatrolRole.Mortar),
        "wake-calf-free" => new("Pip’s first calf tender","unmanned chain tug","the mothers’ passage","the last drag anchor","nursery signals",PatrolRole.Flanker),
        _ => null
    };
}

public sealed partial class BluewaterCourse
{
    public FleetAction? Squadron { get; }
    public int Field { get; private set; }
    public FleetBoat? Tender { get; private set; }
    public Vector2 Battery { get; private set; }
    public float FlagshipHull { get; private set; }
    public bool GunPrize { get; private set; }
    public bool LooseFormation { get; private set; }
    public Enemy? Picket { get; private set; }
    public string SupportName => GunPrize ? Squadron!.Picket : Squadron!.Tender;
    public string FleetTitle => Field switch { 1 => "Two ships in irons", 2 => "Run the van", _ => "Reduce the shore battery" };
    public Vector2 FleetDestination => Field switch
    {
        1 => Tender!.Position,
        2 when Tender is { Health: <= 0 } && Picket is { Health: > 0 } => Picket.Position,
        3 when FlagshipHull > 0 => Battery,
        _ => Target
    };
    public string FleetOrder => Field switch
    {
        1 => $"Q rescues {Squadron!.Tender}, or board the damaged {Squadron.Picket} with Q.",
        2 when Tender!.Health <= 0 => "The aid boat is down. Break the enemy pennant, then reach the gate.",
        2 => $"Escort {SupportName} through {Squadron!.Road}. R changes its station.",
        3 when FlagshipHull <= 0 => $"Battery silent. Carry the all-clear to the exit and press Q.",
        _ => $"Shoot {Squadron!.Arsenal}, or Q from the aid boat to signal with {Squadron.Signal}."
    };
    bool deployed, sortieSignal;
    int freshScreen;
    float gunClock, escortClock;
    Vector2 screenAxis;
    public void ChangeStation()
    {
        if (Field != 2 || Tender == null || Tender.Health <= 0) return;
        LooseFormation = !LooseFormation;
        Tender.Wake.Clear(); Tender.LastLead = Tender.Position;
        Say(LooseFormation ? "Vara    Out on the beam! She’ll draw their shot clear of our wake." :
            "Lio    Form close astern! Bring her in reach of the carpenter.");
    }
    void SetFleetField()
    {
        if (Squadron == null || Station != jobs.Length - 1) return;
        Field = Leg == 1 ? 1 : Leg == Math.Max(2, Order.Legs / 2) ? 2 : Leg == Order.Legs ? 3 : 0;
        if (Field == 0) return;
        Crossing = false;
        var dir = OceanWorld.Unit(Target - Ship.Position, course);
        screenAxis = new(-dir.Y, dir.X);
        Battery = FindWater(Target - screenAxis * 300, 115);
        deployed = false; gunClock = 2; freshScreen = 0; sortieSignal = false; escortClock = 0;
        Picket = null;
        if (Field == 1) Tender = new(FindWater(Target + screenAxis * 245, 85), 100);
        else if (Tender != null)
        {
            Tender.Position = Field == 3 ? FindWater(Battery + screenAxis * 375, 75) : FindWater(Ship.Position + screenAxis * 150, 65);
            Tender.LastLead = Tender.Position; Tender.Wake.Clear();
        }
        FlagshipHull = 78 + BattleTier * 4;
        Weather.Set(Field == 2 ? Ship.Position * .45f + Target * .55f : Battery, Leg, Station);
    }
    void FleetScreen(Vector2 center)
    {
        var side = screenAxis * (freshScreen % 2 == 0 ? 1 : -1);
        var first = Ship.DropPatrol(EnemyKind.Serpent, FindWater(center + side * 265, 85), 1.05f, true);
        if (first != null) { first.Role = Squadron!.Screen; Picket = first; }
        var second = Ship.DropPatrol(Squadron!.Screen == PatrolRole.Caller ? EnemyKind.Ray : EnemyKind.Crab,
            FindWater(center - side * 235, 85), 1, false);
        if (second != null) second.Role = Squadron.Screen == PatrolRole.Flanker ? PatrolRole.Mortar : PatrolRole.Flanker;
        freshScreen++;
    }
    void FleetSignal()
    {
        switch (Country.Climate)
        {
            case SeaClimate.Bottle:
            case SeaClimate.Sleep:
            case SeaClimate.Cinder:
                Ship.Shots.RemoveAll(s => s.Hostile);
                foreach (var craft in fleet) craft.Health = Math.Min(craft.Maximum, craft.Health + 28);
                break;
            case SeaClimate.Tin:
            case SeaClimate.Wax:
            case SeaClimate.Delta:
            case SeaClimate.Loom:
                foreach (var enemy in Ship.Enemies.Where(e => e.Health > 0))
                    enemy.Position = Ship.World.Slide(enemy.Position, enemy.Position + screenAxis * (Country.Climate == SeaClimate.Delta ? 260 : -260), enemy.Radius);
                Ship.Boost = 100;
                break;
            case SeaClimate.Calving:
            case SeaClimate.Orchard:
                foreach (var enemy in Ship.Enemies.Where(e => e.Health > 0))
                {
                    enemy.Stunned = 3.5f;
                    Ship.Events.Add(new("pull", Battery, 3, enemy.Position));
                }
                break;
            case SeaClimate.Salt:
            case SeaClimate.Pitch:
            case SeaClimate.Shelf:
                foreach (var bank in banks) bank.Broken = true;
                Ship.Patch(24);
                break;
            case SeaClimate.Drum:
            case SeaClimate.Choir:
                WeatherRead = true;
                foreach (var enemy in Ship.Enemies) enemy.Role = PatrolRole.Pursuit;
                break;
            case SeaClimate.Court:
                if (Picket is { Health: > 0 }) { Picket.Health = 0; Purse += 4; }
                break;
            case SeaClimate.Storm:
                foreach (var enemy in Ship.Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(e.Position, Battery) < 660 * 660).ToArray())
                    Ship.Rake(enemy);
                break;
        }
        foreach (var enemy in Ship.Enemies)
            if (Vector2.DistanceSquared(enemy.Position, Battery) < 380 * 380) enemy.Stunned = Math.Max(enemy.Stunned, 3);
    }
    void WorkFleetField(float dt, bool hook)
    {
        var tender = Tender!;
        var ship = Ship.Position;
        gunClock -= dt;
        if (Field == 1)
        {
            if (!deployed && Vector2.DistanceSquared(ship, Target) < 960 * 960) { FleetScreen(Battery); deployed = true; }
            if (hook && Picket is { Health: > 0 } enemy && enemy.Health < enemy.MaxHealth * .70f && Vector2.DistanceSquared(ship, enemy.Position) < 230 * 230)
            {
                HookAt(enemy.Position); enemy.Health = 0; GunPrize = true;
                tender.Health = tender.Maximum = 84;
                Say($"Vara    {Squadron!.Picket} strikes her colors. Her guns are ours at the next reach.");
                Purse += 6; Step(); return;
            }
            if (hook && Vector2.DistanceSquared(ship, tender.Position) < 195 * 195)
            {
                HookAt(tender.Position); Kits++; Purse += 3;
                Say($"Lio    {Squadron!.Tender} is clear. We’ll meet her at {Squadron.Road}.");
                Step(); return;
            }
            if (deployed && gunClock <= 0 && Picket is { Health: > 0 })
            {
                Ship.Lob(Picket.Position, Vector2.Lerp(ship, tender.Position, .34f), 10, 104); gunClock = 4.1f;
            }
        }
        else if (Field == 2)
        {
            if (tender.Health > 0)
            {
                var offset = LooseFormation ? screenAxis * 230 : -OceanWorld.Unit(Ship.Velocity, course) * 105;
                var lead = Ship.World.IsWater(ship + offset, 55) ? ship + offset : ship;
                if (Vector2.DistanceSquared(tender.Position, lead) > 86 * 86) FollowWake(tender, lead, dt);
                if (Vector2.DistanceSquared(tender.Position, ship) > 850 * 850)
                {
                    tender.Wake.Clear(); tender.LastLead = tender.Position;
                    Say("Lio    Ease the sheets. The aid boat is falling behind!");
                }
                if (Ship.Events.Any(e => e.Kind == "bossExplosion" && Vector2.DistanceSquared(e.Position, tender.Position) < e.Value * e.Value))
                {
                    tender.Health = Math.Max(0, tender.Health - 9);
                    Ship.Events.Add(new("hurt", tender.Position, 9));
                }
                escortClock -= dt;
                if (escortClock <= 0)
                {
                    escortClock = 1;
                    if (Ship.Enemies.Any(e => e.Health > 0 && e.Stunned <= 0 && Vector2.DistanceSquared(e.Position, tender.Position) < 145 * 145))
                    {
                        tender.Health = Math.Max(0, tender.Health - (LooseFormation ? 4 : 6));
                        Ship.Events.Add(new("hurt", tender.Position, 5));
                    }
                    else if (!LooseFormation && Vector2.DistanceSquared(ship, tender.Position) < 175 * 175) tender.Health = Math.Min(tender.Maximum, tender.Health + 1);
                }
            }
            float distance = Vector2.Distance(ship, Target);
            if (freshScreen == 0 && distance < 1800 || freshScreen == 1 && distance < 720) FleetScreen(Vector2.Lerp(ship, Target, .43f));
            if (gunClock <= 0 && Picket is { Health: > 0 } picket && tender.Health > 0)
            {
                gunClock = GunPrize ? 3.1f : 4.1f;
                if (GunPrize) { Ship.Events.Add(new("arc", tender.Position, 1, picket.Position)); Ship.Rake(picket); }
                else Ship.Lob(picket.Position, tender.Position + OceanWorld.Unit(Ship.Velocity) * 60, 10, 100);
            }
            if (distance < 230 && (tender.Health > 0 ? Vector2.DistanceSquared(tender.Position, Target) < 530 * 530 : Picket is not { Health: > 0 }))
            {
                Purse += tender.Health > 0 ? 8 : 2;
                Say(tender.Health > 0 ? $"Vara    {SupportName} made it. She’ll be on station at the battery." : "Lio    We saved the hands. We’ll have to deal with the battery ourselves.");
                Step(); return;
            }
        }
        else
        {
            if (!deployed && Vector2.DistanceSquared(ship, Battery) < 870 * 870)
            {
                FleetScreen(Battery); deployed = true;
            }
            if (deployed && FlagshipHull > 0)
            {
                float hp = FlagshipHull; DamageProp(Battery, ref hp); FlagshipHull = Math.Max(0, hp);
                if (gunClock <= 0)
                {
                    gunClock = 4;
                    if (Squadron!.Screen == PatrolRole.Caller) AddRaider(Battery - screenAxis * 220, freshScreen++);
                    else if (Squadron.Screen == PatrolRole.Flanker)
                    {
                        Ship.Lob(Battery, ship + screenAxis * 100, 11, 121); Ship.Lob(Battery, ship - screenAxis * 100, 11, 121);
                    }
                    else Ship.Lob(Battery, ship + Ship.Velocity * .38f, 19, 164);
                }
                if (hook && !sortieSignal && tender.Health > 0 && Vector2.DistanceSquared(ship, tender.Position) < 225 * 225)
                {
                    sortieSignal = true; HookAt(tender.Position);
                    Ship.Events.Add(new("arc", tender.Position, 5, Battery));
                    FlagshipHull = Math.Max(0, FlagshipHull - (GunPrize ? 110 : 77) * tender.Health / tender.Maximum);
                    FleetSignal();
                    Purse += 4;
                    Say("Vara    There! We sent the signal. Through the gap!");
                    return;
                }
                if (FlagshipHull <= 0) Ship.Events.Add(new("explosion", Battery, 180));
            }
            if (FlagshipHull <= 0 && hook && Vector2.DistanceSquared(ship, Target) < 215 * 215) { HookAt(Target); Step(); return; }
        }
        if (hook) HookEnemy();
    }
}
