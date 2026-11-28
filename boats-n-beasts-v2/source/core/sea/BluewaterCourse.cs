using System.Numerics;

namespace BoatsNBeasts.Core;

public enum ChartPhase { Passage, Running, Refit, Boss, Port, Won, Lost }
public enum SeaJob { Tow, Guide, Relieve, Salvage, Unload, Track, Bait, DriveOff, Sound, Cut, Relay }
public sealed class FleetBoat(Vector2 position, float hitPoints, bool prize = false)
{
    public bool Prize { get; } = prize;
    public Vector2 Position = position;
    public Vector2 Bow = -Vector2.UnitY;
    public float Health = hitPoints, Maximum = hitPoints;
    public float HitCooldown;
    public Vector2 LastLead = position;
    public Queue<Vector2> Wake { get; } = new();
}

public sealed partial class BluewaterCourse
{
    public CampaignOrder Order { get; }
    public Loadout Outfit { get; }
    public SeaWrit Writ { get; }
    public string DepartureId { get; }
    public string Region { get; private set; }
    public SeaCountry Country { get; private set; }
    public SeaWeather Weather { get; private set; }
    public Voyage Ship { get; }
    public ChartPhase Phase { get; private set; } = ChartPhase.Passage;
    public int Leg { get; private set; } = 1;
    public int Station { get; private set; }
    public int StationCount => jobs.Length;
    public SeaJob Job => jobs[Math.Clamp(Station, 0, jobs.Length - 1)];
    public Vector2 Target { get; private set; }
    public Vector2 Mooring { get; private set; }
    public bool Docked { get; private set; }
    public bool RedPassage { get; private set; }
    public int Purse { get; private set; }
    public int Kits { get; private set; }
    public float HookCooldown { get; private set; }
    public float HookReach => 490 + lineRank * 75 + (Outfit == Loadout.Longline ? 175 : 0);
    public float HookTime { get; private set; }
    public Vector2 HookEnd { get; private set; }
    public string CrewLine { get; private set; } = "";
    public float Speech { get; private set; }
    public IReadOnlyList<FleetBoat> Fleet => fleet;
    public bool SalvageTow => fleet.Any(b=>b.Prize);
    public float GateHealth { get; private set; }
    public Enemy? Captain { get; private set; }
    public Vector2 CannonTarget => Field == 3 ? Battery : Crossing ? Prize : Phase == ChartPhase.Boss && BossCovered ? ShieldPoint : Target;
    public bool HasGunneryTarget => Field == 3 && FlagshipHull>0 || Field==0 && (Phase == ChartPhase.Running && (Crossing ? Order.Duty == SeaDuty.Blockade : Job == SeaJob.Cut) || Phase == ChartPhase.Boss && BossCovered && Order.Duty == SeaDuty.Blockade);
    public bool BossCovered { get; private set; }
    public Vector2 ShieldPoint { get; private set; }
    public int Seals { get; private set; }
    public float Alarm { get; private set; }
    public string RefitName(int index) => index switch { 0 => "Caulk and canvas", 1 => "Longline spool", _ => Outfit == Loadout.Lifeboat ? "Stock the sickbay" : "Double-shot carriage" };
    public string RefitDetail(int index) => index switch
    {
        0 => "Repair 35 hull, mend the convoy, and load a kit.",
        1 => "Extend Lio’s reach and shorten the hook recovery.",
        2 when Outfit == Loadout.Lifeboat => "Load two repair kits for the coming water.",
        _ => Ship.Weapons[0] < 5 ? "Fit another gun to each salvo." : "Improve the crew’s reload."
    };
    readonly List<FleetBoat> fleet = [];
    readonly OceanWorld pilot;
    SeedRandom random;
    SeaJob[] jobs = [SeaJob.Guide];
    Vector2 course;
    bool guardsSent;
    int lineRank, alertCount;
    float patrolDistance, repairCooldown;
    Vector2 beforeTravel;

    public BluewaterCourse(CampaignOrder order, int seed, int stores, Loadout outfit = Loadout.Standard)
    {
        Order = order;
        Outfit = outfit;
        Writ = SeaWrit.For(order);
        Squadron = FleetAction.For(order.Id);
        foreach(char c in string.IsNullOrEmpty(order.Island)?order.Id:order.Island) islandPattern=(islandPattern*31+c)%977;
        Region = order.Region;
        Country = SeaCountry.At(order.Region, order.Island);
        Weather = new(Country);
        random = new((uint)seed ^ 0xd30061u);
        Ship = new((uint)seed, BoatKind.Cutter, 1) { Charted = true, BroadsideRig = outfit == Loadout.Broadside };
        Ship.HullRank = Math.Clamp(stores, 0, 2);
        Ship.Health = Ship.MaxHealth;
        Kits = 1 + Math.Clamp(stores, 0, 2) + (outfit == Loadout.Lifeboat ? 2 : 0);
        pilot = new(Ship.World.Seed);
        var sector = new Vector2(11000 + (int)Country.Climate * 3600, -6200 - order.Tier * 1850);
        pilot.Stream(sector);
        var island = pilot.Places.Where(p=>p.Kind==PlaceKind.Island && p.Radius>=145 && p.Radius<820)
            .MinBy(p=>Vector2.DistanceSquared(p.Position,sector));
        island ??= pilot.Places.Where(OceanWorld.IsSolid).MinBy(p=>Vector2.DistanceSquared(p.Position,sector));
        DepartureId = island?.Id ?? "";
        if(island!=null)
        {
            var side = new Vector2(.83f,.56f);
            var shore=island.Shape?.Point(MathF.Atan2(side.Y,side.X))??side*island.Radius;
            Ship.Position=FindWater(island.Position+shore*1.07f+side*185,80);
            Ship.World.Stream(Ship.Position);
        }
        int atBerth = order.Id switch { "cinder-float" => 3, "cinder-pilots" => 1, _ => 0 };
        if(order.SeaStations is {Length:>0} local && !local.Contains(SeaJob.Tow) &&
            (order.Duty == SeaDuty.Convoy || local.Contains(SeaJob.Guide))) atBerth=Math.Max(1,atBerth);
        for (int i=0; i<atBerth; i++) fleet.Add(new(FindWater(Ship.Position + new Vector2(80 + i*60, 65 + i*85),60),118));
        float angle = random.Range(-.94f,.94f);
        course = new(MathF.Sin(angle), -MathF.Cos(angle));
    }

    public void ChoosePassage(bool red)
    {
        if (Phase != ChartPhase.Passage) return;
        if (Order.Id is "north-return" or "north-index")
        {
            string[] ports = ["The Unnumbered Sea","Sable Court","Choir Deep","Tangleloom Sound","Whitewake Shelf","Hanging Orchard","Reedglass Delta","Cinder Narrows"];
            Region = ports[(Leg-1) % ports.Length];
            Country = SeaCountry.At(Region);
            Weather = new(Country);
        }
        RedPassage = red;
        Docked = false;
        Station = 0;
        float bearing = (red ? .57f : -.43f) + random.Range(-.19f,.19f);
        course = Vector2.TransformNormal(course, Matrix3x2.CreateRotation(bearing));
        jobs = Order.SeaStations is {Length:>0} localJobs ? localJobs : Itinerary();
        Phase = ChartPhase.Running;
        SetStation();
        Mooring = FindWater(Ship.Position + (Target - Ship.Position) * .70f + new Vector2(-course.Y, course.X) * (red ? 665 : 270), 135);
        Say(red ? "Vara    Red pennant. Take the prize water and keep the guns loaded." :
            "Lio    Lee pennant. The pilot marked a friendly mooring on our beam.");
    }

    SeaJob[] Itinerary() => Order.Id switch
    {
        "cinder-pilot" => Leg switch
        {
            1 => [SeaJob.Tow, SeaJob.Sound, SeaJob.Guide],
            2 => [SeaJob.Tow, SeaJob.Cut, SeaJob.Relay],
            3 => [SeaJob.Tow, SeaJob.DriveOff, SeaJob.Guide],
            _ => [SeaJob.Sound, SeaJob.Guide, SeaJob.Relay]
        },
        "cinder-float" => [SeaJob.Cut, Leg % 2 == 0 ? SeaJob.Sound : SeaJob.DriveOff, SeaJob.Guide],
        "cinder-pilots" => [SeaJob.Cut, Leg % 2 == 0 ? SeaJob.Guide : SeaJob.DriveOff, SeaJob.Relay],
        _ => DutyJobs()
    };

    SeaJob[] DutyJobs() => Order.Duty switch
    {
        SeaDuty.Convoy when fleet.Count < Math.Min(Order.Legs, Writ.Lighters) => [SeaJob.Tow, Leg % 2 == 0 ? SeaJob.Cut : SeaJob.Guide, SeaJob.Relay],
        SeaDuty.Convoy => [SeaJob.Sound, RedPassage ? SeaJob.DriveOff : SeaJob.Guide, SeaJob.Relay],
        SeaDuty.Salvage => Leg % 2 == 1 ? [SeaJob.Track, SeaJob.Salvage, SeaJob.Unload] : [SeaJob.Cut, SeaJob.Salvage, SeaJob.Unload],
        SeaDuty.Hunt => [SeaJob.Track, Leg % 2 == 0 ? SeaJob.Sound : SeaJob.Bait, SeaJob.DriveOff],
        SeaDuty.Sounding => [SeaJob.Sound, RedPassage ? SeaJob.Cut : SeaJob.Track, SeaJob.Sound, SeaJob.Relay],
        SeaDuty.Blockade => [SeaJob.Cut, Leg % 2 == 1 ? SeaJob.DriveOff : SeaJob.Salvage, Leg % 2 == 1 ? SeaJob.Relay : SeaJob.Unload],
        _ => [SeaJob.Guide, SeaJob.Relieve, SeaJob.Relay]
    };

    Vector2 FindWater(Vector2 near, float clearance)
    {
        pilot.Stream(near);
        for (int ring = 0; ring <= 12; ring++)
        {
            for (int j = 0; j < (ring == 0 ? 1 : 12); j++)
            {
                float angle = j * MathF.Tau / 12 + ring * .39f;
                var p = near + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * (ring * 125);
                if (pilot.IsWater(p, clearance)) return p;
            }
        }
        return Ship.Position;
    }

    void SetStation()
    {
        var side = new Vector2(-course.Y, course.X);
        float distance = Job is SeaJob.Tow or SeaJob.Bait ? 890 : 1650 + random.Range(0, 650) + Math.Min(7,Order.Tier) * 95;
        float bend = Station % 2 == 0 ? 410 : -380;
        Target = FindWater(Ship.Position + course * distance + side * (bend + random.Range(-250,250)), Job == SeaJob.Guide ? 240 : 145);
        guardsSent = false;
        Alarm = 0;
        GateHealth = 28 + Order.Tier * 4;
        patrolDistance = 0;
        beforeTravel = Ship.Position;
        Weather.Set(Target,Leg,Station);
        SetCrossing();
        SetFleetField();
        LayBanks();
    }

    public void Refit(int choice)
    {
        if (Phase != ChartPhase.Refit || choice < 0 || choice > 2) return;
        if (choice == 0)
        {
            Ship.Patch(35); Kits++;
            foreach (var boat in fleet) boat.Health = Math.Min(boat.Maximum, boat.Health + 40);
        }
        else if (choice == 1) lineRank = Math.Min(5, lineRank + 1);
        else if (Outfit == Loadout.Lifeboat) Kits += 2;
        else if (Ship.Weapons[0] < 5) Ship.Weapons[0]++;
        else Ship.ReloadRank++;
        Leg++;
        Phase = ChartPhase.Passage;
    }

    public void Tick(float dt, SailInput input, bool hook, bool patch)
    {
        if (Phase is ChartPhase.Passage or ChartPhase.Refit or ChartPhase.Won or ChartPhase.Lost || Ship.Mode == VoyageMode.Upgrade) return;
        Alarm = Math.Max(0, Alarm - dt);
        HookCooldown = Math.Max(0,HookCooldown - dt);
        HookTime = Math.Max(0,HookTime - dt);
        Speech = Math.Max(0,Speech - dt);
        repairCooldown -= dt;
        if (patch && Kits > 0 && repairCooldown <= 0 && (Ship.Health < Ship.MaxHealth || fleet.Any(b => b.Health < b.Maximum)))
        {
            Kits--; Ship.Patch(Outfit == Loadout.Lifeboat ? 55 : 39); repairCooldown = 2;
            foreach (var boat in fleet) boat.Health = Math.Min(boat.Maximum, boat.Health + (Outfit == Loadout.Lifeboat ? 35 : 21));
            Say("Vara    That's the worst of the leaks stuffed.");
        }
        Ship.EscortPosition = fleet.Count > 0 ? fleet[^1].Position : null;
        Ship.Tick(dt,input);
        if (Ship.Mode == VoyageMode.Defeat) { Phase = ChartPhase.Lost; return; }
        if(Phase==ChartPhase.Running)TickBanks(dt);
        WorkLine(dt,input);
        AlertQuietWater(input.Fire,dt);
        TickFleet(dt);
        if (Phase == ChartPhase.Lost) return;
        if (Phase != ChartPhase.Port && !WeatherRead) Weather.Tick(dt,Ship,Order.Tier);
        if (Phase == ChartPhase.Running)
        {
            if (!Docked && hook && Vector2.Distance(Ship.Position,Mooring) < 160)
            {
                Docked = true; Kits++; Ship.Patch(23); Purse += RedPassage ? 3 : 1;
                foreach (var boat in fleet) boat.Health = Math.Min(boat.Maximum, boat.Health + 20);
                Say("Lio    Drinking water, spare canvas and a sling for the next watch.");
                return;
            }
            if (Field != 0) WorkFleetField(dt,hook);
            else if (Crossing) NavigateCrossing(dt,hook);
            else TickJob(hook);
        }
        else if (Phase == ChartPhase.Boss) TickCaptain(hook, dt);
        else if (Phase == ChartPhase.Port && hook && Vector2.Distance(Ship.Position,Target) < 235)
        {
            Purse += 7 + Order.Tier * 2;
            Phase = ChartPhase.Won;
        }
    }

    void TickFleet(float dt)
    {
        var lead = Ship.Position;
        foreach (var boat in fleet)
        {
            var delta = lead - boat.Position;
            float distance = delta.Length();
            boat.HitCooldown -= dt;
            if (distance > 105)
            {
                FollowWake(boat,lead,dt);
                if (distance > 1900) { Phase = ChartPhase.Lost; Say("Lio    The convoy's beyond hailing distance. We must turn back for her crew."); return; }
            }
            bool blasted = Ship.Events.Any(e => e.Kind is "bossExplosion" or "pufferExplosion" && Vector2.Distance(e.Position,boat.Position) < e.Value);
            if (boat.HitCooldown <= 0 && (blasted || Ship.Enemies.Any(e => e.Health > 0 && e.Stunned <= 0 && Vector2.Distance(e.Position,boat.Position) < e.Radius + 50)))
            {
                boat.Health -= (Writ.Delicate ? 12 : 7) + Math.Min(Order.Tier,8); boat.HitCooldown = 2.8f;
                Ship.Events.Add(new("hurt",boat.Position,8));
                if (boat.Health <= 0) { Phase = ChartPhase.Lost; Say("Lio    Her bottom's gone. Take off the hands!"); return; }
            }
            lead = boat.Position;
        }
    }

    void FollowWake(FleetBoat boat,Vector2 lead,float dt)
    {
        float distance=Vector2.Distance(lead,boat.Position);
        if (Vector2.DistanceSquared(lead,boat.LastLead) > 56*56)
        {
            boat.Wake.Enqueue(lead);
            boat.LastLead = lead;
        }
        while (boat.Wake.TryPeek(out var passed) && Vector2.DistanceSquared(boat.Position,passed)<80*80) boat.Wake.Dequeue();
        var waypoint = boat.Wake.TryPeek(out var next) ? next : lead;
        var desired = OceanWorld.Unit(waypoint-boat.Position);
        var steer = desired;
        float towSpeed = Math.Min(Ship.Speed * 1.75f, (distance - 86) * 3.1f);
        boat.Bow = OceanWorld.Unit(Vector2.Lerp(boat.Bow, steer, Math.Min(1,dt * 4)),desired);
        float step=Math.Min(towSpeed*dt,Vector2.Distance(boat.Position,waypoint));
        var nextPosition=Ship.World.Slide(boat.Position,boat.Position+steer*step,24);
        if(Vector2.DistanceSquared(boat.Position,nextPosition)<step*step*.04f && boat.Wake.Count>1)
            boat.Wake.Dequeue();
        boat.Position=Phase==ChartPhase.Running?FloatAroundBanks(nextPosition):nextPosition;
    }

    public float Notice { get; private set; }
    float heardCooldown;
    void AlertQuietWater(bool fire,float dt)
    {
        if(!Writ.Quiet || Phase!=ChartPhase.Running)return;
        heardCooldown-=dt;
        Notice=Math.Clamp(Notice + (fire ? .55f : -.35f)*dt,0,1);
        if(Notice<1 || heardCooldown>0)return;
        heardCooldown=9;
        Ship.DropPatrol(EnemyKind.Ray,Ship.Position+new Vector2(-course.Y,course.X)*580,1.25f,false);
        Say("Lio    Listen. Another lamp ship heard that shot. The line will work in quiet water.");
    }

    void Say(string line) { CrewLine = line; Speech = 5; }
}
