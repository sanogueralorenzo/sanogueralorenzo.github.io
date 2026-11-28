using System.Numerics;

namespace BoatsNBeasts.Core;

public enum InquiryKind { Soundings, Evacuation, Lanterns }
public enum InquiryStep { Assign, Diver, Purchase, Recover, Exhibit, Pilot, Medicine, Escort, Lamp, Shadow, Testimony, Report }
public readonly record struct WatchSite(string Kind, string Label, Vector2 Point);

public sealed class PrizeInquiry
{
    public InquiryKind Kind { get; }
    public InquiryStep Step { get; private set; } = InquiryStep.Assign;
    public Vector2 Clinic { get; }
    public Vector2 Diver { get; }
    public Vector2 Examiner { get; }
    public Vector2 Anchorage { get; }
    public Vector2 Windlass { get; }
    public Vector2 Lead { get; private set; }
    public Vector2 Rival { get; private set; }
    public Vector2 RivalBow { get; private set; } = Vector2.UnitY;
    public float RivalGear { get; private set; } = 65;
    public bool Overhauled => RivalGear <= 0;
    public bool Contested { get; private set; }
    public bool WitnessSaved { get; private set; }
    public bool Original { get; private set; }
    public bool Escorted { get; private set; }
    public bool LampOut { get; private set; }
    public int Exposures { get; private set; }
    public int Portage { get; private set; }
    public bool Finished { get; private set; }
    public bool Diverted { get; private set; }
    public int Gate { get; private set; }
    public Vector2[] Lamps { get; }
    public Vector2[] Samples { get; }
    public Vector2 Runner { get; private set; }
    public int Plaque { get; }
    public Vector2 ShadowBow => new(MathF.Cos(turn), MathF.Sin(turn));
    public bool LampVisible => Kind == InquiryKind.Lanterns && Step is InquiryStep.Shadow or InquiryStep.Testimony;
    public float LightRadius => LampOut ? 330 : 485;
    public bool RivalOn => !Overhauled && !Diverted;
    public bool HasPilot => Step == InquiryStep.Escort;
    public string RivalName => Kind switch { InquiryKind.Soundings => "The Double Warrant", InquiryKind.Evacuation => "The Removal Tug", _ => "The False Witness" };
    public string Title => Kind switch { InquiryKind.Soundings => "The diver and the duplicate", InquiryKind.Evacuation => "The sick berth", _ => "The court’s dark lantern" };
    readonly PrizeTheater watch;
    readonly Vector2 heading, cross;
    readonly Queue<Vector2> wake = [];
    float turn, volley = 3, lanternHit, line;
    Vector2 lastLead;
    float pinned;
    public PrizeInquiry(PrizeTheater theater, Func<Vector2, float, Vector2> water, Vector2 direction, int seed)
    {
        watch = theater; heading = direction; cross = new(-direction.Y, direction.X); Plaque = (seed & int.MaxValue) % 3;
        Kind = watch.Operation switch
        {
            PrizeOperation.Registry or PrizeOperation.Saboteur => InquiryKind.Soundings,
            PrizeOperation.ChainGang or PrizeOperation.Courier => InquiryKind.Evacuation,
            _ => InquiryKind.Lanterns
        };
        var start = watch.Ship.Position;
        Vector2 At(float ahead, float over, float radius = 100) => water(start + heading * ahead + cross * over, radius);
        Diver = At(530, -375); Clinic = At(510, 420); Examiner = At(1530, -260);
        Anchorage = At(1610, 530); Lead = At(180, -630); Windlass = water(Diver + cross * 405 - heading * 75, 75);
        Rival = At(1570, 40); Runner = At(900, 130); lastLead = Lead;
        Lamps = [At(530, 230), At(840, -295), At(1330, 310)];
        Samples = [At(810, -150), At(1000, -385), At(975, 75)];
    }
    public Vector2? Alternative => Step switch { InquiryStep.Assign => Kind == InquiryKind.Lanterns ? Examiner : Lead, InquiryStep.Shadow when Gate == 0 && !LampOut => Diver, _ => null };
    public bool AlternativeSelected { get; private set; }
    public void NextBearing() { if (Alternative.HasValue) AlternativeSelected = !AlternativeSelected; }
    public Vector2 Bearing => AlternativeSelected && Alternative.HasValue ? Alternative.Value : Goal;
    public string BearingName => !AlternativeSelected || !Alternative.HasValue ? Label : Step == InquiryStep.Shadow ? "Keeper’s shutter" : Kind == InquiryKind.Lanterns ? "Open hearing" : "Witness launch";
    public string Label => Step switch
    {
        InquiryStep.Assign => Kind == InquiryKind.Lanterns ? "Night pilot" : Kind == InquiryKind.Evacuation ? "Infirmary launch" : "Diving boat",
        InquiryStep.Diver => "Diving boat",
        InquiryStep.Purchase => "Winch purchase",
        InquiryStep.Recover => Contested && RivalOn ? RivalName : "Exhibit float",
        InquiryStep.Exhibit => "Stamp examiner",
        InquiryStep.Pilot => "Witness launch",
        InquiryStep.Medicine => "Infirmary launch",
        InquiryStep.Escort => Gate == 0 ? "Hospital gate" : "Sheltered roadstead",
        InquiryStep.Lamp => "Lantern keeper",
        InquiryStep.Shadow => $"Shutter {Math.Min(Gate + 1, 3)}",
        InquiryStep.Testimony => "Court packet",
        _ => "Pilot’s hearing"
    };
    public Vector2 Goal => Step switch
    {
        InquiryStep.Assign => Kind == InquiryKind.Lanterns ? Lead : Kind == InquiryKind.Evacuation ? Clinic : Diver,
        InquiryStep.Diver => Diver,
        InquiryStep.Purchase => Windlass,
        InquiryStep.Recover => Contested && RivalOn ? Rival : Samples[Plaque],
        InquiryStep.Exhibit => Examiner,
        InquiryStep.Pilot => Lead,
        InquiryStep.Medicine => Clinic,
        InquiryStep.Escort => Gate == 0 ? Lamps[2] : Anchorage,
        InquiryStep.Lamp => Diver,
        InquiryStep.Shadow => Lamps[Math.Min(Gate, 2)],
        InquiryStep.Testimony => Runner,
        _ => Examiner
    };
    public string Directions => Step switch
    {
        InquiryStep.Assign => Kind switch
        {
            InquiryKind.Soundings => "Q at the diving boat for the original, or the witness launch to shelter the witness first.",
            InquiryKind.Evacuation => "Q at the infirmary for medicine, or board the witness launch first for a quicker, exposed evacuation.",
            _ => "Q at the night pilot to borrow her dark lantern, or at the examiner to enter openly with your witnesses."
        },
        InquiryStep.Diver => "Take Lio to the diving skiff. Q puts him over the side with a lifting line.",
        InquiryStep.Purchase => "Vara needs a crosswise pull. Sail to the winch float and Q to lift the sealed boxes.",
        InquiryStep.Recover => Contested && RivalOn ? "The rival has the exhibit. Fire on her rig or get alongside and Q to cut her towline." : $"Find the {new[] { "striped", "crossed", "spotted" }[Plaque]} float. Q takes its case aboard.",
        InquiryStep.Exhibit => "Q at the examiner to match the owner’s mark against the salvaged object.",
        InquiryStep.Medicine => "Q at the infirmary launch transfers the surgeon and her blue medicine chest.",
        InquiryStep.Pilot => Kind == InquiryKind.Soundings ? "Q aboard the witness launch takes down the diver’s independent account." : "Get alongside the moving witness launch. Q passes the doctor and secures the tow.",
        InquiryStep.Escort => "Lead the witness through the hospital gate. Use X to send an ally to draw the rival aside.",
        InquiryStep.Lamp => "Q borrows the keeper’s shutter. It shortens the rival searchlight, but alerts the gunboat.",
        InquiryStep.Shadow => "Q at each shutter to dim the court lights. Cross behind the moving search beam.",
        InquiryStep.Testimony => "Hail the traveling witness packet. A dark approach keeps its passengers free of the rival.",
        _ => "Q presents both sides at the pilot’s hearing. The examiner releases the public ship marks."
    };
    public IEnumerable<WatchSite> Sites()
    {
        if (Step == InquiryStep.Assign)
        {
            if (Kind == InquiryKind.Soundings) yield return new("convoy", "Witness first", Lead);
            if (Kind == InquiryKind.Evacuation) yield return new("convoy", "Fast evacuation", Lead);
            if (Kind == InquiryKind.Lanterns) yield return new("refuge", "Open hearing", Examiner);
        }
        if (Step == InquiryStep.Recover && !Contested)
        {
            string[] marks = ["Striped float", "Crossed float", "Spotted float"];
            for (int i = 0; i < 3; i++) yield return new("wreck", marks[i], Samples[i]);
        }
        else yield return new(Step switch { InquiryStep.Escort or InquiryStep.Shadow or InquiryStep.Purchase => "gate", InquiryStep.Exhibit or InquiryStep.Report => "refuge", _ => "convoy" }, Label, Goal);
        if (HasPilot) yield return new("convoy", "Witness in tow", Lead);
        if (Step == InquiryStep.Shadow && Gate == 0 && !LampOut) yield return new("refuge", "Borrow keeper’s shutter", Diver);
    }
    public void SendPilot()
    {
        if (!RivalOn) return;
        if (watch.SpendPilot()) { Diverted = true; watch.Say("An allied cutter borrows the prize flag. The rival follows it out of the channel."); }
        else watch.Say("An independent pilot must sign aboard first. Pass a civilian at a hail, or recruit at a refit.");
    }
    public void Tick(float dt, bool hook)
    {
        var ship = watch.Ship; turn += dt * .47f; volley -= dt; line -= dt; lanternHit -= dt;
        if (!HasPilot && Step != InquiryStep.Assign && Kind == InquiryKind.Evacuation)
            Lead = Move(Lead, Clinic + cross * (280 * MathF.Cos(turn * .32f)) - heading * 290, 61, dt);
        Runner = Move(Runner, Lamps[(int)(turn * .16f) % 3], 62, dt);
        if (RivalOn)
        {
            Vector2 prey = Step switch
            {
                InquiryStep.Purchase or InquiryStep.Recover => Samples[Plaque],
                InquiryStep.Escort => Lead,
                InquiryStep.Shadow => Lamps[(Gate + 1) % 3],
                InquiryStep.Exhibit => Examiner,
                _ => Runner
            };
            if (Contested && Step == InquiryStep.Recover) prey = Vector2.DistanceSquared(Rival, Anchorage) > 180 * 180 ? Anchorage : Diver;
            var aim = OceanWorld.Unit(prey - Rival, RivalBow); RivalBow = OceanWorld.Unit(Vector2.Lerp(RivalBow, aim, Math.Min(1, dt)), aim);
            Rival = Move(Rival, prey, Step == InquiryStep.Recover ? 101 : 73, dt);
            foreach (var shot in ship.Shots.Where(s => !s.Hostile && s.Life > 0))
            {
                if (Vector2.DistanceSquared(shot.Position, Rival) > 85 * 85) continue;
                RivalGear = Math.Max(0, RivalGear - shot.Damage); ship.Events.Add(new("hit", Rival, shot.Damage)); shot.Life = 0;
                if (Overhauled) { watch.AwardPrize(5); watch.Say("The rival strikes her pennant. Vara lowers a boat for her crew."); break; }
            }
            if (!Overhauled && volley <= 0 && Vector2.Distance(ship.Position, Rival) < 648 && (Contested || Step == InquiryStep.Escort || watch.Alarm > 1))
            { ship.Lob(Rival, ship.Position + ship.Velocity * .37f, 7 + Math.Min(watch.Order.Tier / 2, 5), 82); volley = 6.3f; }
            if (Step == InquiryStep.Recover && Vector2.Distance(Rival, Samples[Plaque]) < 133 && !Contested)
            { Contested = true; watch.Say("The Double Warrant has taken the exhibit in tow. Sail close and cut its rope."); }
        }
        if (LampVisible && RivalOn && lanternHit <= 0 && Vector2.Distance(ship.Position, Rival) < LightRadius &&
             Vector2.Dot(OceanWorld.Unit(ship.Position - Rival), ShadowBow) > .94f)
        { lanternHit = 5.6f; Exposures++; watch.RaiseAlarm(); ship.Lob(Rival, ship.Position, 8, 91); watch.Say("The court searchlight found the cutter. Vara calls the fall of shot."); }
        if (HasPilot)
        {
            Lead = PrizeTheater.Trail(watch.Ship, Lead, wake, ref lastLead, ref pinned, dt, 86);
            if (Vector2.Distance(ship.Position, Goal) < 163 && Vector2.Distance(Lead, Goal) < 465)
            {
                if (Gate++ == 0) watch.Say("The doctor raises her lantern. Lead the witness into the lee at the second flag.");
                else { WitnessSaved = Escorted = true; Set(InquiryStep.Report, "The surgeon takes the witness ashore. Take the signed testimony to the pilot."); }
                return;
            }
        }
        if (!hook || line > 0) return;
        bool At(Vector2 p, float r = 190) => Vector2.DistanceSquared(ship.Position, p) < r * r;
        if (Step == InquiryStep.Assign)
        {
            if (Kind == InquiryKind.Soundings && At(Lead)) { WitnessSaved = true; Set(InquiryStep.Diver, "Vara takes the witness aboard. The rival has a head start on the exhibit."); return; }
            if (Kind == InquiryKind.Evacuation && At(Lead)) { Escorted = false; StartEscort(); watch.RaiseAlarm(); return; }
            if (Kind == InquiryKind.Lanterns && At(Examiner)) { watch.RaiseAlarm(); Set(InquiryStep.Testimony, "The examiner raises your public pennant. The court packet is moving under a gunboat’s eye."); return; }
            if (!At(Goal)) return;
            if (Kind == InquiryKind.Evacuation) { Escorted = true; Set(InquiryStep.Pilot, "The surgeon has her chest. Bring her alongside the witness launch."); }
            else if (Kind == InquiryKind.Lanterns) Set(InquiryStep.Shadow, "The pilot knows the shutters. Slip behind the searchlight or borrow the keeper’s hood.");
            else Set(InquiryStep.Purchase, "Lio is diving. He waves a lifting line toward the crosswind float.");
            return;
        }
        if (Step == InquiryStep.Shadow && Gate == 0 && !LampOut && At(Diver)) { LampOut = true; watch.RaiseAlarm(); watch.Say("The keeper closes one leaf of the light. The beam shrinks."); line = .55f; return; }
        if (Step == InquiryStep.Recover && !Contested)
        {
            int nearest = Enumerable.Range(0, 3).MinBy(i => Vector2.DistanceSquared(ship.Position, Samples[i]));
            if (At(Samples[nearest], 132) && nearest != Plaque) { watch.RaiseAlarm(); watch.Say("The wax carries a copyist’s mark. The other floats still carry their cases."); line = .8f; return; }
        }
        if (!At(Goal, Step == InquiryStep.Recover && Contested ? 210 : 190)) return;
        switch (Step)
        {
            case InquiryStep.Diver: Set(InquiryStep.Purchase, "Lio takes his tools over the side. Haul across the wind at the winch float."); break;
            case InquiryStep.Purchase: Set(InquiryStep.Recover, "The crates break the surface. The witness described the marked float."); break;
            case InquiryStep.Recover:
                Original = true; watch.AwardPrize(3); if (Contested && RivalOn) watch.RaiseAlarm();
                Set(InquiryStep.Exhibit, $"Vara dries {watch.Exhibit.Item}. Bring it to the stamp examiner."); break;
            case InquiryStep.Exhibit:
                Set(WitnessSaved ? InquiryStep.Report : InquiryStep.Pilot, $"The examiner sees {watch.Exhibit.Mark}. The bonded locker should hold the counterpart."); break;
            case InquiryStep.Pilot:
                if (Kind == InquiryKind.Soundings) { WitnessSaved = true; Set(InquiryStep.Report, "The diver’s account agrees with the work on the object. Read both into the public roll."); }
                else StartEscort(); break;
            case InquiryStep.Shadow:
                Gate++; if (Gate == 3) Set(InquiryStep.Testimony, "All three shutters are dark. The court packet can now come alongside.");
                else Set(InquiryStep.Shadow, "The keeper douses her lantern. Take the next shutter from behind the beam."); break;
            case InquiryStep.Testimony:
                WitnessSaved = true;
                if (Exposures == 0) { watch.AwardPrize(4); Escorted = true; }
                Set(InquiryStep.Report, "The packet has its independent copy and a living witness. Bring them to the pilot."); break;
            case InquiryStep.Report: Finished = true; watch.SealDocket(WitnessSaved, Original, Escorted); break;
        }
    }
    void StartEscort()
    {
        Gate = 0; lastLead = watch.Ship.Position; wake.Clear();
        Set(InquiryStep.Escort, Escorted ? "The surgeon is aboard. Lead the launch through both flags." : "The crew casts off at once. Keep the rival away from their unprotected launch.");
    }
    void Set(InquiryStep step, string call) { Step = step; AlternativeSelected = false; line = .45f; watch.Say(call); }
    Vector2 Move(Vector2 p, Vector2 target, float speed, float dt)
    {
        var d = target - p; var dist = d.Length();
        return dist < .5f ? p : watch.Ship.World.Slide(p, p + d / dist * Math.Min(speed * dt, dist), 24);
    }
}
