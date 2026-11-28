using System.Numerics;

namespace BoatsNBeasts.Core;

public readonly record struct FleetBearing(string Kind, string Name, Vector2 Position);
public sealed partial class FleetCommand
{
    public int Cabin { get; private set; }
    public int Slings { get; private set; }
    public bool ClinicIssued { get; private set; }
    public int HouseLine { get; private set; }
    public bool PilotFlag { get; private set; }
    public int Warped { get; private set; } = -1;
    public int Sightings { get; private set; }
    public bool Surrendered { get; private set; }
    public bool Boarders { get; private set; }
    public int HomeGate { get; private set; }
    public bool NamedSignal => Sightings >= 2;
    public bool FalseLight { get; private set; }
    public Vector2 Decoy { get; private set; }
    public Vector2 Fog { get; private set; }
    public int PressedCompany { get; private set; }
    public Vector2 LeadEnd => Field == FleetField.Rescue ? Stations[1].Position : Field == FleetField.Passage && Warped >= 0 ? Stations[Warped].Position : Field == FleetField.Captain ? Stations[0].Position : Ship.Position;
    public bool LeadOn => Field == FleetField.Rescue && HouseLine == 1 || Field == FleetField.Passage && Warped >= 0 || Field == FleetField.Captain && gunLead;
    public bool Clouds => Field == FleetField.Captain && GunsDown >= 2;
    public float FogWidth => 173 + variant * 7;
    public Vector2 HandsPoint => TaskForHands().Point;
    public string HandsLabel => TaskForHands().Label;
    public string HandsMessage { get; private set; } = "";
    Vector2 housePurchase, coastLight, firstRope, outerHome, innerHome;
    Vector2[] towForks = [], leePins = [], hotPins = [];
    readonly HashSet<int> medicine = [];
    bool gunLead;
    float handCooldown;
    (Vector2 Point, string Label) TaskForHands()
    {
        if (Pilot != null) return (Pilot.Goal, Pilot.Label);
        if (NextPilot is { } role && HullsAfloat > 0)
        {
            var keeper = Watchkeeper(role);
            return (keeper.Position, $"Take the {role.ToString().ToLowerInvariant()} helm from {keeper.Skipper}");
        }
        if (Field == FleetField.Rescue)
        {
            if (ClinicIssued && Slings == 0 && Allies.All(a => !a.Afloat || !medicine.Contains((int)a.Role)) && Cabin == 0) return (Refuge, "Restock the surgeon’s slings");
            if (!ClinicIssued || Cabin > 0) return (Refuge, Cabin > 0 ? "Land survivors" : "Collect rescue slings");
            var loaded = Allies.Where(a => a.Afloat && a.People > 0).MinBy(a => Vector2.DistanceSquared(a.Position, Ship.Position));
            if (loaded != null) return (loaded.Position, "Take survivors from " + loaded.Name);
            var needs = Allies.Where(a => a.Afloat && a.Assignment >= 0 && Stations[a.Assignment].Task == FleetTask.Rescue && !medicine.Contains((int)a.Role))
                .OrderBy(a => a.Assignment).FirstOrDefault();
            if (needs != null && Slings > 0) return (needs.Position, "Pass slings to " + needs.Name);
            if (Stations[1].Stock > 0 && HouseLine < 2) return HouseLine == 0 ? (Stations[1].Position, "Catch the roof’s bowline") : (housePurchase, "Pull across the wind");
            var post = Stations.FirstOrDefault(p => p.Task == FleetTask.Rescue && !p.Done);
            return (post?.Position ?? Refuge, post != null ? "Meet the rescue boat" : "Return to the hospital");
        }
        if (Field == FleetField.Passage)
        {
            if (!PilotFlag) return (Stations[2].Position, "Take the pilot pennant");
            if (Warped >= 0) return (leePins[Warped], "Lead the warp to the lee pin");
            var arrived = Enumerable.Range(0, 2).FirstOrDefault(i => Stations[i].Gate == 2 && !Stations[i].Done, -1);
            if (arrived >= 0) return (Stations[arrived].Berth, "Land the sealed cargo");
            var waiting = Enumerable.Range(0, 2).Where(i => Stations[i].Gate == 0 && !Stations[i].Done)
                .OrderByDescending(i => Stations[i].AtFork).ThenBy(i => Vector2.DistanceSquared(Stations[i].Position, Ship.Position)).FirstOrDefault(-1);
            if (waiting >= 0) return (Stations[waiting].Position, "Take the lighter’s warp");
            var underway = Stations.Take(2).FirstOrDefault(p => !p.Done);
            return (underway?.Berth ?? Center, "Meet the receiving clerk");
        }
        if (Field == FleetField.Captain)
        {
            if (gunLead) return (firstRope, "Break the crane’s purchase");
            if (GunsDown < 2)
            {
                var ready = Stations.Take(2).Where(p => !p.Done).OrderByDescending(p => p.Work >= 2)
                    .ThenBy(p => Vector2.DistanceSquared(p.Position, Ship.Position)).First();
                return (ready.Position, ready == Stations[0] ? "Take the gun tackle" : "Lift the magazine key");
            }
            if (Sightings == 0) return (Stations[2].Position, "Copy the company signal");
            if (Sightings == 1) return (ClearCoast(), "Read the second bearing");
            if (EnemyStrength > 0) return (EnemyHull, "Strike the identified rig");
            return (EnemyHull, Boarders ? "Accept the surrender" : "Meet the boarding hull");
        }
        if (Field == FleetField.Refuge)
            return HomeGate switch { 0 => (outerHome, "Hoist the outer company flag"), 1 => (innerHome, "Bring the consort through"), _ => (Refuge, "Q  Sign at the refuge") };
        return (Ship.Position, "Wait for orders");
    }
    void PrepareHands(FleetField field)
    {
        handCooldown = 0; HandsMessage = "";
        switch (field)
        {
            case FleetField.Rescue:
                housePurchase = Water(Stations[1].Position + side * 420 - heading * 160, 85);
                break;
            case FleetField.Passage:
                towForks = [At(555, -270), At(530, 330)];
                leePins = [At(755, -575), At(825, 580)];
                hotPins = [At(885, -80), At(895, 95)];
                break;
            case FleetField.Captain:
                firstRope = Water(Stations[0].Position + side * 340 - heading * 190, 86);
                coastLight = At(1080, -350);
                break;
            case FleetField.Refuge:
                outerHome = At(330, -370); innerHome = At(720, 255); Refuge = At(990, -165, 135);
                Stations[0].Position = outerHome;
                break;
        }
    }
    public IEnumerable<FleetBearing> Workmarks()
    {
        if (Field == FleetField.Rescue)
        {
            yield return new("port", "Hospital tender", Refuge);
            if (HouseLine < 2) yield return new("gate", "Roof purchase", housePurchase);
        }
        if (Field == FleetField.Passage)
        {
            for (int i = 0; i < 2; i++)
            {
                if (Stations[i].Done) continue;
                yield return new("gate", i == 0 ? "Western fork" : "Eastern fork", towForks[i]);
                if (Stations[i].Gate == 0) { yield return new("chain", "Covered warp pin", leePins[i]); yield return new("picket", "Exposed warp pin", hotPins[i]); }
                yield return new("port", "Receiver’s berth", Stations[i].Berth);
            }
        }
        if (Field == FleetField.Captain)
        {
            if (!Stations[0].Done) yield return new("chain", "Gun tackle", firstRope);
            if (GunsDown == 2 && Sightings < 2) yield return new("gate", "Coast witness", ClearCoast());
        }
        if (Field == FleetField.Refuge)
        {
            if (HomeGate == 0) yield return new("gate", "Outer company flag", outerHome);
            if (HomeGate < 2) yield return new("chain", "Consort chain", innerHome);
        }
    }
    Vector2 ClearCoast()
    {
        Vector2[] candidates = [coastLight, coastLight - side * 180, coastLight + heading * 200, coastLight + side * 192];
        foreach (var p in candidates) if (Ship.World.IsWater(p, 55) && ClearSight(p, EnemyHull)) return p;
        return coastLight;
    }
    public bool ClearSight(Vector2 from, Vector2 to)
    {
        var d = to - from; float t = Math.Clamp(Vector2.Dot(Fog - from, d) / Math.Max(1, d.LengthSquared()), 0, 1);
        return Vector2.DistanceSquared(Fog, from + d * t) > FogWidth * FogWidth;
    }
    public bool Hands()
    {
        if (!AtSea || handCooldown > 0) return false;
        if (Pilot != null) { bool worked = Pilot.Interact(); CreditPilot(); return worked; }
        if (NextPilot is { } role) return BoardPilot(role);
        bool Near(Vector2 p, float r = 183) => Vector2.DistanceSquared(Ship.Position, p) < r * r;
        void Note(string message) { HandsMessage = message; Say(message); handCooldown = .48f; }
        if (Field == FleetField.Rescue)
        {
            if (Near(Refuge) && (Cabin > 0 || !ClinicIssued || Slings == 0))
            {
                Rescued += Cabin; Silver += 3 * Cabin; Cabin = 0; ClinicIssued = true; Slings = Math.Max(2, Slings);
                Note(Rescued == 0 ? "The surgeon passes over two dry lifting slings. Bring them to the crews at the wrecks." : "The clinic has the survivors. Fresh slings are on the cutter."); return true;
            }
            var hand = Allies.Where(a => a.Afloat && Near(a.Position) && a.People > 0).MinBy(a => Vector2.DistanceSquared(a.Position, Ship.Position));
            if (hand != null && Cabin < 2)
            {
                int count = Math.Min(2 - Cabin, hand.People); hand.People -= count; Cabin += count; PressedCompany |= 1 << (int)hand.Role;
                Note($"{hand.Skipper} passes {count} across the rail. Land them at the hospital tender."); return true;
            }
            var crew = Allies.Where(a => a.Afloat && Near(a.Position) && a.Assignment >= 0 && Stations[a.Assignment].Task == FleetTask.Rescue && !medicine.Contains((int)a.Role))
                .MinBy(a => Vector2.DistanceSquared(a.Position, Ship.Position));
            if (crew != null && Slings > 0)
            { medicine.Add((int)crew.Role); Slings--; PressedCompany |= 1 << (int)crew.Role; Note(crew.Skipper + " has the surgeon’s sling and can lift people."); return true; }
            if (HouseLine == 0 && Near(Stations[1].Position))
            {
                bool steadied = Allies.Any(a => a.Afloat && a.Assignment == 1 && Vector2.DistanceSquared(a.Position, Stations[1].Position) < 180 * 180);
                if (!steadied) { Note("Send a hull to hold the roof steady before taking its bowline."); return false; }
                HouseLine = 1; Note("The bowline is aboard. Sail across the wind to the orange purchase and haul again."); return true;
            }
            if (HouseLine == 1 && Near(housePurchase))
            { HouseLine = 2; Silver += 3; Note("The overturned roof rolls upright. The second rescue crew can reach its passengers."); return true; }
        }
        if (Field == FleetField.Passage)
        {
            if (!PilotFlag && Near(Stations[2].Position))
            {
                var spot = Allies.FirstOrDefault(a => a.Afloat && a.Assignment == 2 && a.Signals > 0);
                if (spot == null) { Note("A hull must read the signal mast while the cutter takes the pilot pennant."); return false; }
                PilotFlag = true; PressedCompany |= 1 << (int)spot.Role; Note(spot.Skipper + " passes the pilots’ pennant aboard. Join the first lighter at the forks."); return true;
            }
            if (Warped >= 0)
            {
                int i = Warped;
                if (!Near(leePins[i]) && !Near(hotPins[i])) return false;
                bool hot = Vector2.DistanceSquared(Ship.Position, hotPins[i]) < Vector2.DistanceSquared(Ship.Position, leePins[i]);
                Stations[i].Gate = 1; Warped = -1; Silver += hot ? 5 : 2;
                if (hot) Lanes.Add(new(Signature, Stations[i].Position, hotPins[i], 86, 1.45f));
                Note(hot ? "The exposed pin opens a direct cut. The watch battery is turning." : "The lee warp holds. The lighter is clear to tow into its own berth."); return true;
            }
            for (int i = 0; i < 2; i++)
            {
                var p = Stations[i]; if (p.Done) continue;
                if (p.Gate == 2 && Near(p.Berth))
                { p.Done = true; Delivered++; Silver += 6; Note("The receiver counts the cargo onto the quay. The escort is free for a new task."); return true; }
                if (PilotFlag && p.Gate == 0 && Near(p.Position) && p.AtFork)
                { Warped = i; Note("The warp is across the cutter’s stern. Choose the covered pin or lead it through the battery to the exposed one."); return true; }
            }
        }
        if (Field == FleetField.Captain)
        {
            if (gunLead && Near(firstRope)) { gunLead = false; BreakDevice(Stations[0]); Note("The cutter hauls the crane over. Its gun crew abandons the purchase."); return true; }
            if (GunsDown < 2)
            {
                for (int i = 0; i < 2; i++)
                {
                    var p = Stations[i]; if (p.Done || !Near(p.Position)) continue;
                    var party = Allies.FirstOrDefault(a => a.Afloat && a.Assignment == i && Vector2.DistanceSquared(a.Position, p.Position) < 170 * 170);
                    if (p.Work < 2 || party == null) { Note("Send a hull to take the far side of the device. The cutter will work the near side."); return false; }
                    PressedCompany |= 1 << (int)party.Role;
                    if (i == 0) { gunLead = true; Note("The far crew pays out the tackle. Take the cutter to the orange fall and haul it down."); }
                    else { BreakDevice(p); Note("The opposite crew pins the swivel while the cutter takes its firing key."); }
                    return true;
                }
            }
            else if (Sightings == 0 && Near(Stations[2].Position))
            {
                var spot = Allies.FirstOrDefault(a => a.Afloat && a.Assignment == 2 && a.Signals > 0);
                if (spot == null) { Note("Post a hull at the signal mast to give the cutter its first bearing."); return false; }
                Sightings++; PressedCompany |= 1 << (int)spot.Role; Note($"{spot.Skipper} reads {Signal}. Take a second bearing outside the moving haze."); return true;
            }
            else if (Sightings == 1 && Near(ClearCoast()) && ClearSight(Ship.Position, EnemyHull))
            { Sightings++; Silver += 4; Note($"The two bearings cross on {Order.Boss}. The other hull is flying a borrowed flag. Break the true rig."); return true; }
            else if (Sightings >= 2 && EnemyStrength <= 0 && Near(EnemyHull, 205))
            {
                if (!Boarders) { Note("A friendly hull must board the struck captain before the cutter accepts the colors."); return false; }
                Silver += 12 + Order.Tier; Surrendered = true; Note("The captain yields the colors. Meet the sloop to bring the fugitive packet’s messenger home."); return true;
            }
        }
        if (Field == FleetField.Refuge && HomeGate < 2)
        {
            var post = HomeGate == 0 ? outerHome : innerHome;
            if (Near(post, 175))
            {
                var nearest = Allies.Where(a => a.Afloat).MinBy(a => Vector2.DistanceSquared(a.Position, post));
                if (nearest == null || Vector2.DistanceSquared(nearest.Position, post) > 305 * 305)
                { Note("The cutter needs a second hull inside the pilot gate to exchange the company signal."); return false; }
                HomeGate++; Stations[0].Position = HomeGate == 1 ? innerHome : Refuge; Silver += 2;
                Note(HomeGate == 1 ? "The outer pilot answers. Bring the consort under the inner chain." : "The chain drops behind the flotilla. Moor and sign the tally at the refuge."); return true;
            }
        }
        return false;
    }
}
