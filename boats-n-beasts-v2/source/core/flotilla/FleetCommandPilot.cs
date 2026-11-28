using System.Numerics;

namespace BoatsNBeasts.Core;

public readonly record struct PilotBoom(Vector2 A, Vector2 B, float Radius)
{
    public Vector2 Closest(Vector2 p)
    {
        var span = B - A; float t = Math.Clamp(Vector2.Dot(p - A, span) / Math.Max(1, span.LengthSquared()), 0, 1);
        return A + span * t;
    }
}
public readonly record struct PilotMark(string Name, string Kind, Vector2 Position, int Index);
public sealed class FleetPilot
{
    public FleetRole Role { get; }
    public string Skipper { get; }
    public string Company { get; }
    public string Signal { get; }
    public float Integrity { get; private set; }
    public float Maximum { get; }
    public int Silver { get; private set; }
    public int Step { get; private set; }
    public int Load { get; private set; } = -1;
    public int Gate { get; private set; }
    public int Saved { get; private set; }
    public int Support { get; private set; }
    public bool Won { get; private set; }
    public bool Lost => Integrity <= 0;
    public Vector2 Position { get; private set; }
    public Vector2 Velocity { get; private set; }
    public Vector2 Bow { get; private set; } = -Vector2.UnitY;
    public Vector2 Tow { get; private set; }
    public bool Attached => Load >= 0 && Role != FleetRole.Sloop;
    public Vector2 Home { get; } = new(-750, 505);
    public Vector2 Shot { get; private set; }
    public float Warning { get; private set; }
    public float Splash { get; private set; }
    public float Ward { get; private set; }
    public float Clock { get; private set; }
    public string Call { get; private set; } = "";
    public int Subject { get; private set; }
    public List<PilotBoom> Obstacles { get; } = [];
    public string Title => Role switch { FleetRole.Tender => "The lifeboat watch", FleetRole.Tug => "The broken lock", _ => "The answering pennants" };
    public string Label => Role switch
    {
        FleetRole.Tender when Step == 1 => "Put the survivor ashore",
        FleetRole.Tender => new[] { "Catch the missing stoker", "Free the sailmaker", "Tow the surgeon’s pram" }[Math.Min(Subject, 2)],
        FleetRole.Tug when Step == 0 => Subject == 0 ? "Make fast to the broken leaf" : "Lift the stranded barge’s painter",
        FleetRole.Tug when Step == 1 => Gate < 2 ? $"Steer the load through gate {Gate + 1}" : "Set the load on its berth",
        FleetRole.Tug => "Return the tug to the company",
        _ => Step switch
        {
            0 => "Read the first moving yardarm",
            1 => "Return the second pilot’s answer",
            2 => "Cut the fugitive’s fore pennant",
            3 => "Catch the fugitive’s stern messenger",
            _ => "Bring the colors back to the company"
        }
    };
    public string Instructions => Role switch
    {
        FleetRole.Tender => Step == 1 ? "Tow the patient into the marked lee berth. G lowers the stretcher." : Subject == 1 && !cut ? "The sailmaker is under a fallen sail. Space cuts it nearby, then G lifts him." : "Bring the bow to the marked survivor and press G to pass a line.",
        FleetRole.Tug => Step switch
        {
            0 => "G takes the painter. Shift brakes; Space hauls slack out of the tow.",
            1 when Gate < 2 => "Steer both hulls through each pair of flags. Use Space to keep the tow short on the turn.",
            1 => "Bring the load into the receiving cradle, then release it with G.",
            _ => "Take the tug back to its answering ships and press G."
        },
        _ => Step switch
        {
            0 or 1 => "Read the yardarm from its lit side. Sail to its gold bearing and press G.",
            2 => "Come up across the fugitive’s bow. Space cuts the counterfeit fore pennant within gun range.",
            3 => "Pass down the far quarter, take the real messenger with G, then return to the company.",
            _ => "The two wing boats have opened the returning lane. G reports at the pennant."
        }
    };
    readonly Vector2[] shores = [new(-700, 442), new(780, -440), new(-715, 440)];
    readonly Vector2[] subjects = [new(-605, -435), new(665, 425), new(482, -530)];
    readonly Vector2[][] gates = [[new(-240, -160), new(390, -235)], [new(355, 267), new(-330, 240)]];
    readonly bool[] aboard = new bool[3];
    readonly Vector2[] lights = new Vector2[3];
    readonly int variant;
    float hazard = 3.7f, hurt, cool;
    bool cut;
    public FleetPilot(FleetRole role, CommandHull ally, FleetArticles? articles, int seed, int help)
    {
        Role = role; Skipper = ally.Skipper; Company = ally.Name; Signal = articles?.Signal ?? "the company pennant";
        Maximum = ally.Maximum; Integrity = Math.Max(1, ally.Hull); Support = Math.Clamp(help, 1, 3); variant = seed & 3;
        Position = Home; Tow = Home; Call = $"{Skipper} gives the captain the working helm of {Company}.";
        Obstacles.Add(new(new(-410, -520), new(-205, -350), 39));
        Obstacles.Add(new(new(55, -15), new(265, 24), 45));
        Obstacles.Add(new(new(-390, 350), new(-236, 484), 33));
        Obstacles.Add(new(new(500, -35), new(709, 65), 31));
        if (role == FleetRole.Tug) Obstacles.Add(new(new(100, 355), new(205, 491), 31));
        PlaceLightships();
    }
    public Vector2 Goal => Role switch
    {
        FleetRole.Tender => Step == 1 ? shores[Subject] : Passenger(Subject),
        FleetRole.Tug when Step == 0 => Subject == 0 ? new(-730, -375) : new(704, 485),
        FleetRole.Tug when Step == 1 => Gate < 2 ? gates[Subject][Gate] : Subject == 0 ? new(716, -428) : new(-755, -195),
        FleetRole.Tug => Home,
        _ => Step switch
        {
            0 => lights[0] + new Vector2(-100, 75),
            1 => lights[1] + new Vector2(100, -85),
            2 => lights[2] + BowOf(2) * 153,
            3 => lights[2] - BowOf(2) * 150,
            _ => Home
        }
    };
    public IEnumerable<PilotMark> Marks()
    {
        yield return new("Company berth", "refuge", Home, -1);
        if (Role == FleetRole.Tender)
        {
            for (int i = 0; i < 3; i++) if (!aboard[i] && Load != i) yield return new(new[] { "Stoker", "Sailmaker", "Surgeon" }[i], i == 2 ? "convoy" : "wreck", Passenger(i), i);
            if (Step == 1) yield return new("Hospital berth", "port", shores[Subject], 10);
        }
        if (Role == FleetRole.Tug)
        {
            if (Step == 0) yield return new("Waiting load", "convoy", Goal, 0);
            if (Step == 1 && Gate < 2)
            {
                var at = gates[Subject][Gate];
                yield return new("Port flag", "gate", at + new Vector2(0, -96), 1);
                yield return new("Starboard flag", "gate", at + new Vector2(0, 96), 2);
            }
            if (Step == 1 && Gate == 2) yield return new("Receiving cradle", "port", Goal, 3);
        }
        if (Role == FleetRole.Sloop)
        {
            for (int i = 0; i < 3; i++) yield return new(i == 2 ? "Fleeing packet" : "Wing pilot", i == 2 ? "picket" : "convoy", lights[i], i);
        }
    }
    Vector2 Passenger(int i)
    {
        float a = Clock * (.15f + i * .026f) + variant + i;
        return subjects[i] + new Vector2(MathF.Cos(a) * 59, MathF.Sin(a) * 37);
    }
    Vector2 BowOf(int i) => OceanWorld.Unit(new Vector2(-MathF.Sin(Clock * (.17f + i * .021f) + i + variant), MathF.Cos(Clock * (.17f + i * .021f) + i + variant)));
    void PlaceLightships()
    {
        Vector2[] anchor = [new(-552, -413), new(613, 435), new(689, -360)];
        for (int i = 0; i < 3; i++)
        {
            float a = Clock * (.17f + i * .021f) + i + variant;
            lights[i] = anchor[i] + new Vector2(MathF.Cos(a) * 159, MathF.Sin(a) * 111);
        }
    }
    public bool CallShipmate(Shipmate mate)
    {
        if (mate == Shipmate.Vara) return Mend();
        if (mate == Shipmate.Nell) { Ward = Math.Max(Ward, 4); Warning = 0; Call = "Nell sounds four quiet beats across the water."; return true; }
        if (mate == Shipmate.Lio && Attached)
        { Tow = Float(Vector2.Lerp(Tow, Position, .56f), Role == FleetRole.Tug ? 36 : 15, false); Call = "Lio shortens the painter around the stern bollard."; return true; }
        return false;
    }
    public bool Mend()
    {
        if (Integrity >= Maximum) return false;
        Integrity = Math.Min(Maximum, Integrity + 32); Call = "The company passes over a repair kit."; return true;
    }
    public void Cover()
    {
        if (Support <= 0 || Ward > 0) return;
        Support--; Ward = 5.5f; Warning = 0; hazard = 5; Call = "The company clears a lane with a crossfire. The held signal buys one more close approach.";
    }
    public void Tick(float dt, SailInput input)
    {
        if (Won || Lost) return; Clock += dt; cool -= dt; hurt -= dt; Ward = Math.Max(0, Ward - dt);
        PlaceLightships();
        var move = OceanWorld.Unit(input.Move);
        float speed = Role == FleetRole.Tender ? 171 : Role == FleetRole.Tug ? 143 : 221;
        if (Attached) speed *= Role == FleetRole.Tug ? .88f : .81f;
        if (input.Boost) speed *= Role == FleetRole.Tug ? .52f : 1.26f;
        float grip = Role == FleetRole.Tug ? 1.75f : Role == FleetRole.Tender ? 4.2f : 3.3f;
        var current = new Vector2(MathF.Sin(Position.Y * .004f + Clock * .35f), MathF.Cos(Position.X * .0035f + variant)) * (Role == FleetRole.Tug ? 15 : 8);
        Velocity = Vector2.Lerp(Velocity, move * speed + current, Math.Clamp(dt * grip, 0, 1));
        if (move.LengthSquared() > .01f) Bow = OceanWorld.Unit(Vector2.Lerp(Bow, move, Math.Min(1, grip * dt)), move);
        Position = Float(Position + Velocity * dt, Role == FleetRole.Tug ? 42 : 28, true);
        if (Attached)
        {
            float rope = Role == FleetRole.Tug ? (input.Fire ? 92 : 144) : 71;
            var d = Position - Tow; if (d.LengthSquared() > rope * rope)
                Tow = Float(Tow + OceanWorld.Unit(d) * Math.Min(d.Length() - rope, dt * (Velocity.Length() + 100)), Role == FleetRole.Tug ? 36 : 15, false);
        }
        if (Role == FleetRole.Tender && Subject == 1 && !cut && input.Fire && Vector2.Distance(Position, Passenger(1)) < 165)
        { cut = true; Call = "The sail parts. Throw the sailmaker the free end of the line."; }
        if (Role == FleetRole.Tug && Step == 1 && Gate < 2)
        {
            var gate = gates[Subject][Gate];
            if (Vector2.Distance(Position, gate) < 199 && Vector2.Distance(Tow, gate) < 163) { Gate++; Silver += 2; Call = Gate == 2 ? "Both gate flags are astern. Set the load down in the cradle." : "The tow has cleared the first pair. Bring it round the second."; }
        }
        if (Role == FleetRole.Sloop && Step == 2 && input.Fire && Vector2.Distance(Position, Goal) < 204)
        { Step = 3; Silver += 3; Call = "The false pennant falls. The real messenger is at the packet’s stern."; }
        Attack(dt);
    }
    Vector2 Float(Vector2 p, float radius, bool pilot)
    {
        p = Vector2.Clamp(p, new(-981, -667), new(981, 667));
        foreach (var boom in Obstacles)
        {
            var q = boom.Closest(p); var d = p - q; float gap = d.Length(), limit = boom.Radius + radius;
            if (gap >= limit) continue;
            var normal = OceanWorld.Unit(d, Vector2.UnitY); p = q + normal * limit;
            if (pilot) Velocity -= normal * Math.Min(0, Vector2.Dot(Velocity, normal));
        }
        return p;
    }
    void Attack(float dt)
    {
        Splash = Math.Max(0, Splash - dt);
        if (Warning > 0)
        {
            Warning -= dt;
            if (Warning <= 0)
            {
                Splash = .65f;
                if (Ward <= 0 && hurt <= 0 && (Vector2.DistanceSquared(Position, Shot) < 121 * 121 || Attached && Vector2.DistanceSquared(Tow, Shot) < 78 * 78))
                { Integrity = Math.Max(0, Integrity - 9); hurt = 1.5f; Call = "Shot comes aboard. The hull is taking water."; }
            }
        }
        else if ((hazard -= dt) <= 0)
        {
            hazard = 6.5f; Shot = Position + Velocity * .72f; Warning = 2.05f;
        }
    }
    public bool Interact()
    {
        if (Won || Lost || cool > 0) return false;
        var gap = Vector2.Distance(Position, Goal);
        if (gap > 153) return false;
        cool = .55f;
        if (Role == FleetRole.Tender)
        {
            if (Step == 0)
            {
                if (Subject == 1 && !cut) { Call = "Cut the fallen sail with Space before taking the patient."; return false; }
                Load = Subject; Tow = Passenger(Subject); Step = 1; Call = "The line holds. Bring the patient to the hospital showing the same pennant.";
            }
            else
            {
                if (Vector2.Distance(Tow, Goal) > 207) { Call = "Bring the stretcher fully into the lee of the berth."; return false; }
                aboard[Subject] = true; Saved++; Load = -1; Silver += 4; Subject++; Step = 0;
                if (Subject >= 3) { Subject = 2; Won = true; Call = "All three displaced hands are safe. The tender rejoins the company."; }
                else Call = Subject == 1 ? "A sailmaker is caught under a wet spritsail. Cut it free before throwing a line." : "The surgeon will not leave without the medicine pram. Bring both across.";
            }
            return true;
        }
        if (Role == FleetRole.Tug)
        {
            if (Step == 0) { Load = Subject; Tow = Goal; Gate = 0; Step = 1; Call = "The painter holds. Take the gate leaf between both pairs of pilot flags."; return true; }
            if (Step == 1 && Gate == 2 && Vector2.Distance(Tow, Goal) < 213)
            {
                Silver += 6; Load = -1; Subject++; Step = Subject == 2 ? 2 : 0;
                Call = Step == 2 ? "The lock is clear and the second load is in. Rejoin the witnesses." : "The leaf has found its hinges. The yard lighter can now be brought through in the opposite direction."; return true;
            }
            if (Step == 2) { Won = true; return true; }
            return false;
        }
        if (Step == 2) { Call = "Bring the gun across the fleeing fore pennant and fire."; return false; }
        if (Step == 4) { Won = true; Silver += 4; return true; }
        Step++; Silver += 2;
        Call = Step switch { 1 => $"The first pilot repeats {Signal}. Carry the answer to the other moving wing.", 2 => "The two signals identify the black packet. Come up across its fore pennant.", 4 => "The messenger is aboard. Bring the real colors home.", _ => Call };
        return true;
    }
}
