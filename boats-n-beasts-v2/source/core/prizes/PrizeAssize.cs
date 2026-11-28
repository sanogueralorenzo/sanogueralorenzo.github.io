using System.Numerics;

namespace BoatsNBeasts.Core;

public enum AssizeStep { Choose, Serve, Reader, Contest, Seal, Loose, Magazine, Challenge, Transfer }
public enum CourtManeuver { Broadside, Net, Ram, Ember }
public sealed class PrizeAssize
{
    public AssizeStep Step { get; private set; }
    public bool Public { get; private set; }
    public bool Finished { get; private set; }
    public int Turn { get; private set; }
    public int Objections { get; private set; }
    public int Hands { get; private set; }
    public int Cut { get; private set; }
    public Vector2 Bench { get; private set; }
    public Vector2 Barge { get; private set; }
    public Vector2 Pilot { get; private set; }
    public Vector2 Quarter { get; private set; }
    public Vector2 Forward { get; private set; }
    public Vector2 Kedge { get; private set; }
    public Vector2 Clerk { get; private set; }
    public Vector2 Flank { get; private set; }
    public Vector2 SlashFrom { get; private set; }
    public Vector2 SlashTo { get; private set; }
    public float WindUp { get; private set; }
    public float Radius { get; private set; }
    public CourtManeuver Move { get; private set; }
    public bool Exposed => exposed > 0;
    public int Witnesses => Math.Min(watch.Prisoners, 3) + (watch.CommissionWon ? 2 : 0);
    public int Remaining => Math.Max(0, 3 - Cut);
    public bool Alternative { get; private set; }
    public bool CanSwitch => Step is AssizeStep.Choose or AssizeStep.Contest or AssizeStep.Challenge;
    public Vector2 Primary => Step switch
    {
        AssizeStep.Choose => Bench,
        AssizeStep.Serve => Pilot,
        AssizeStep.Reader => Clerk,
        AssizeStep.Contest => Exposed ? Quarter : Pilot,
        AssizeStep.Seal => Bench,
        AssizeStep.Loose => Kedge,
        AssizeStep.Magazine => Forward,
        AssizeStep.Challenge => Exposed ? Quarter : Flank,
        _ => Barge
    };
    public Vector2 Goal => Alternative && CanSwitch ? Step == AssizeStep.Choose ? Kedge : Quarter : Primary;
    public string Label => Step switch
    {
        AssizeStep.Choose => Alternative ? "Seizure launch" : "Public court",
        AssizeStep.Serve => "Witness pilot",
        AssizeStep.Reader => "Reader’s packet",
        AssizeStep.Contest => Exposed || Alternative ? "Marshal’s quarter" : "Counter-witness",
        AssizeStep.Seal => "Floating bench",
        AssizeStep.Loose => "Kedge tackle",
        AssizeStep.Magazine => "Fore magazine",
        AssizeStep.Challenge => Exposed || Alternative ? "Marshal’s quarter" : "Broadside raft",
        _ => "Bonded prize"
    };
    public string Instruction => Step switch
    {
        AssizeStep.Choose => "Choose a public hearing at the bench or cut the kedge at the seizure launch. Tab changes bearing.",
        AssizeStep.Serve => "Take the sworn witnesses by boat. Hail their pilot with Q.",
        AssizeStep.Reader => "Catch the moving reader’s packet and Q to hand over the independent record.",
        AssizeStep.Contest => $"The marshal objects. Q at a witness to answer, or hook her exposed quarter. Objections answered {Objections}/3.",
        AssizeStep.Seal => "Bring the finding to the floating bench. Q has the clerk seal the award.",
        AssizeStep.Loose => $"Q at the marked kedge to free a detained boat. Keels freed {Cut}/3.",
        AssizeStep.Magazine => "Q at the fore magazine to turn its swivel onto the marshal’s flag. Dodge her return fire.",
        AssizeStep.Challenge => "Fire at the marshal’s swivel or Q at the broadside raft to turn it. Q at her bare quarter cuts a line.",
        _ => "Q alongside the bonded ship to transfer the case and take up her tow."
    };
    readonly PrizeTheater watch;
    readonly Vector2[] road, berths;
    readonly Vector2 side, head;
    float clock, cadence = 3, exposed, hot, net, gun = 36;
    int readerPilot;
    readonly int family;
    public PrizeAssize(PrizeTheater theater, Func<Vector2, float, Vector2> water, Vector2 travel, int seed)
    {
        watch = theater; head = travel; side = new(-head.Y, head.X);
        Vector2 At(float longitudinal, float lateral, float radius = 115) => water(watch.Ship.Position + head * longitudinal + side * lateral, radius);
        road = [At(960, -335), At(1580, 140), At(1260, 570), At(750, 150)];
        berths = [At(505, -420), At(1280, -590), At(1755, 100)];
        Bench = At(460, 195); Barge = At(1680, 385); Pilot = berths[0]; Quarter = road[0]; Forward = road[1];
        Kedge = berths[0]; Clerk = road[2]; Flank = road[3]; family = ((seed & 63) + (int)watch.Country.Climate) % 4;
    }
    public void Cycle() { if (CanSwitch) Alternative = !Alternative; }
    public IEnumerable<WatchSite> Sites()
    {
        yield return new("court", "Floating public bench", Bench);
        if (Step == AssizeStep.Choose) { yield return new("chain", "Seizure launch", Kedge); yield break; }
        yield return new("prize", "Bonded prize", Barge);
        yield return new("picket", Exposed ? "Marshal’s bare quarter" : "Marshal’s cutter", Quarter);
        if (Step is AssizeStep.Serve or AssizeStep.Contest) yield return new("convoy", "Witness pilot", Pilot);
        if (Step == AssizeStep.Reader) yield return new("convoy", "Reader’s packet", Clerk);
        if (Step == AssizeStep.Loose) yield return new("chain", "Detained keel", Kedge);
        if (Step == AssizeStep.Challenge) yield return new("convoy", "Broadside raft", Flank);
        if (Step == AssizeStep.Magazine) yield return new("picket", "Fore magazine", Forward);
    }
    public void Tick(float dt, bool hook)
    {
        var ship = watch.Ship; clock += dt; hot -= dt; exposed -= dt; cadence -= dt; net -= dt;
        if (Step != AssizeStep.Choose)
        {
            var bow = OceanWorld.Unit(road[(int)(clock / 7) % 4] - Quarter);
            Quarter = ship.World.Slide(Quarter, Quarter + bow * (Exposed ? 29 : 67) * dt, 28);
            Clerk = Along(Clerk, road[((int)(clock / 9) + readerPilot + 1) % 4], 76, dt);
            if (Step == AssizeStep.Contest) Pilot = Along(Pilot, berths[Objections % 3], 87, dt);
            if (Step == AssizeStep.Reader) Pilot = Along(Pilot, ship.Position, Math.Min(150, (ship.Position - Pilot).Length()), dt);
        }
        if (Step is AssizeStep.Contest or AssizeStep.Loose or AssizeStep.Magazine or AssizeStep.Challenge)
        {
            if (WindUp > 0)
            {
                WindUp -= dt;
                if (WindUp <= 0) Release();
            }
            else if (cadence <= 0 && Near(Quarter, 775)) Telegraph();
            if (net > 0 && Vector2.DistanceSquared(ship.Position, SlashTo) < Radius * Radius) ship.Velocity *= MathF.Pow(.38f, dt);
            foreach (var shot in ship.Shots.Where(s => !s.Hostile && s.Life > 0))
            {
                if (Vector2.DistanceSquared(shot.Position, Quarter) > 93 * 93) continue;
                if (Vector2.Dot(OceanWorld.Unit(ship.Position - Quarter), OceanWorld.Unit(Bench - Quarter)) < -.65f && !Exposed) continue;
                gun -= shot.Damage; shot.Life = 0; ship.Events.Add(new("hit", Quarter, shot.Damage));
                if (gun <= 0) { gun = 36; exposed = 4.8f; WindUp = 0; cadence = 5.4f; watch.Say("Vara has cut the swivel tackle. Hook the marshal’s bare quarter."); }
            }
        }
        if (!hook || hot > 0 || Finished) return;
        switch (Step)
        {
            case AssizeStep.Choose:
                if (Near(Kedge, 160) && Vector2.DistanceSquared(ship.Position, Kedge) < Vector2.DistanceSquared(ship.Position, Bench))
                { Public = false; Set(AssizeStep.Loose, "The seizure launch takes your line. Release the three detained keels under the marshal’s eye."); }
                else if (Near(Bench, 178)) { Public = true; Set(AssizeStep.Serve, "The bench is open. Give the witnesses passage before the marshal removes them."); }
                break;
            case AssizeStep.Serve:
                if (Near(Pilot, 175)) { Hands = Witnesses; Set(AssizeStep.Reader, "The witnesses name the reader by her traveling packet. Catch her before she rounds the roads."); }
                break;
            case AssizeStep.Reader:
                if (Near(Clerk, 171)) { readerPilot++; Hands++; if (watch.CommissionWon) Objections++; Set(AssizeStep.Contest, watch.Exhibit.Finding); }
                break;
            case AssizeStep.Contest:
                if (Near(Pilot, 173))
                {
                    var statement = Objections switch { 0 => watch.Exhibit.Mark, 1 => watch.Exhibit.Finding, _ => "The rescued witnesses identify the sealed original." };
                    if (Hands > 0) Hands--; else watch.RaiseAlarm();
                    Objections++; Pilot = berths[Objections % 3]; watch.AwardPrize(2); hot = .65f;
                    watch.Say(statement); if (Objections >= 3) Set(AssizeStep.Seal, "The marshal has no further objection. The clerk lowers the seal from the public bench.");
                }
                else if (Exposed && Near(Quarter, 196)) { exposed = 0; Objections++; watch.AwardPrize(1); hot = .7f; if (Objections >= 3) Set(AssizeStep.Seal, "The marshal yields her last objection."); }
                break;
            case AssizeStep.Seal:
                if (Near(Bench, 184)) { watch.AwardPrize(2 + Hands); Set(AssizeStep.Transfer, "The clerk seals the award against the independent finding. Take custody of the prize."); }
                break;
            case AssizeStep.Loose:
                if (Near(Kedge, 154))
                {
                    Cut++; Kedge = berths[Cut % 3]; hot = .65f; watch.AwardPrize(2); watch.Say("The detained lighter sheers away. The marshal shifts her battery.");
                    if (Cut >= 3) { Cut = 0; Set(AssizeStep.Magazine, "All three keels have water. Turn the detached fore magazine against the marshal."); }
                }
                break;
            case AssizeStep.Magazine:
                if (Near(Forward, 160)) { exposed = 6.8f; Set(AssizeStep.Challenge, "The swivel fires through the marshal’s tackle. Bring Lio to her quarter."); }
                break;
            case AssizeStep.Challenge:
                if (Exposed && Near(Quarter, 210))
                { Cut++; exposed = 0; hot = .7f; watch.AwardPrize(3); if (Cut >= 2) Set(AssizeStep.Transfer, "Both lines part. The marshal hauls down her flag and releases the bonded prize."); else watch.Say("One restraint parts. Use the broadside raft or Vara’s guns to open her stern again."); }
                else if (Near(Flank, 155)) { exposed = 6.5f; hot = .6f; cadence = 4; watch.Say("The broadside raft slews the marshal across the wind. Her quarter is open."); }
                break;
            case AssizeStep.Transfer:
                if (Near(Barge, 183)) { Finished = true; watch.AwardPrize(Public ? 6 + Hands : 8); watch.TakePrize(Barge); }
                break;
        }
    }
    void Telegraph()
    {
        var ship = watch.Ship;
        Move = (CourtManeuver)((family + Turn++) % 4);
        SlashFrom = Quarter;
        SlashTo = Move == CourtManeuver.Ram ? ship.Position + OceanWorld.Unit(ship.Velocity) * 115 : ship.Position + ship.Velocity * .40f;
        Radius = Move == CourtManeuver.Net ? 139 : Move == CourtManeuver.Ember ? 105 : 66;
        WindUp = Move == CourtManeuver.Ram ? 1.6f : 1.15f; cadence = 5.4f;
    }
    void Release()
    {
        var ship = watch.Ship;
        switch (Move)
        {
            case CourtManeuver.Ram:
                var course = SlashTo - SlashFrom; float projection = Math.Clamp(Vector2.Dot(ship.Position - SlashFrom, course) / Math.Max(1, course.LengthSquared()), 0, 1);
                if (Vector2.Distance(ship.Position, SlashFrom + course * projection) < 84) ship.HullHit(12);
                Quarter = Along(Quarter, SlashTo, 310, 1); exposed = 2.9f; break;
            case CourtManeuver.Net: net = 4f; ship.Lob(Quarter, SlashTo, 5, 79); break;
            case CourtManeuver.Ember:
                ship.Lob(Quarter, SlashTo, 9, 100); ship.Lob(Quarter, SlashTo + side * 145, 7, 77); break;
            default:
                var normal = OceanWorld.Unit(SlashTo - Quarter); normal = new(-normal.Y, normal.X);
                foreach (int i in new[] { -1, 0, 1 }) ship.Lob(Quarter, SlashTo + normal * i * 96, 8, 62); break;
        }
    }
    Vector2 Along(Vector2 p, Vector2 to, float speed, float dt)
    { var d = to - p; float n = d.Length(); return n < 1 ? p : watch.Ship.World.Slide(p, p + d / n * Math.Min(n, speed * dt), 24); }
    bool Near(Vector2 p, float range) => Vector2.DistanceSquared(watch.Ship.Position, p) < range * range;
    void Set(AssizeStep next, string call) { Step = next; Alternative = false; hot = .45f; watch.Say(call); }
}
