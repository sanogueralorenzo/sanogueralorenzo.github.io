using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class LandingYard
{
    public HiddenWorks? Works { get; private set; }
    public WorksStage PassageStage { get; private set; }
    public int HandsSet { get; private set; }
    public int Machinery { get; private set; }
    public bool KeepsakeTaken { get; private set; }
    public bool KeepsakeCarried { get; private set; }
    public bool KeepsakeReturned { get; private set; }
    public bool TookPit { get; private set; }
    public Vector2 Vara { get; private set; }
    public Vector2 Forging { get; private set; }
    public Vector2 Chamber(int room) => Plan.Patches[room].Center;
    public int NextDrum => (Plan.Seed & 1) == HandsSet ? 5 : 6;
    public float ShuttleCycle => Clock * 1.10f + MathF.Abs(Plan.Seed % 23);
    public bool ShuttleInPlay => Phase == YardPhase.Approach && PassageStage == WorksStage.KeyRoom && Machinery < 2 && Works!.Mechanism is InnerWork.Loom or InnerWork.Floodgate;
    public Vector2 ShuttleStart => Chamber(8) + new Vector2(-2.30f, -.56f);
    public Vector2 ShuttleEnd => Chamber(8) + new Vector2(2.30f, .56f);
    public float ShuttleBeat => ShuttleCycle % 4.45f;
    public Vector2 Shuttle => Vector2.Lerp(ShuttleStart, ShuttleEnd, Math.Clamp((ShuttleBeat - 1.25f) / 1.65f, 0, 1));
    public Vector2 MachinePoint(int slot)
    {
        Vector2[] offsets = [new(-1.55f, .53f), new(1.36f, -.79f), new(.16f, 1.42f)];
        return Chamber(8) + offsets[(slot + (int)((uint)Plan.Seed % 3)) % 3];
    }
    bool lioHolding, varaHolding;
    Vector2 lioPost, varaPost;
    void EnterWorks(HiddenWorks works)
    {
        Works = works; Phase = YardPhase.Approach; Plan = new(Order, 0, seed, works);
        Player = Plan.Dock; Mate = Player + new Vector2(.5f, 0); Vara = Player - new Vector2(.55f, 0);
        Say(works.Entry);
    }
    void FollowCrew(float dt)
    {
        if (Works == null) return;
        Vector2 Follow(Vector2 position, Vector2 target)
        {
            var next = Plan.Waypoint(position, Plan.Walkable(target)); var delta = next - position;
            return delta.LengthSquared() < .0001f ? position : Walkable(position + Unit(delta) * Math.Min(delta.Length(), dt * 4.25f));
        }
        Mate = Follow(Mate, lioHolding ? lioPost : Player - Heading * .64f + new Vector2(.26f, 0));
        Vara = Follow(Vara, varaHolding ? varaPost : Player - Heading * 1.03f - new Vector2(.30f, 0));
        if (PassageStage == WorksStage.TwoHands && HandsSet == 2 && Vector2.DistanceSquared(Mate, lioPost) < .18f && Vector2.DistanceSquared(Vara, varaPost) < .18f)
        {
            Plan.OpenDoor(5, 8); Plan.OpenDoor(6, 8); PassageStage = WorksStage.KeyRoom;
            Forging = MachinePoint(0); lioHolding = varaHolding = false;
            Say("Both ratchets catch. The crew lifts the shutters and follows you into the apparatus room.");
        }
    }
    void OpenArchive()
    {
        Plan.OpenDoor(2, 4); Plan.OpenDoor(7, 4); Plan.OpenDoor(1, 7); Plan.OpenDoor(2, 9);
        lioHolding = varaHolding = false; PassageStage = WorksStage.Archive;
        if (TookPit) { Chits += 3; Say("The watch pass opens both shutters. Vara takes three trade chits from the purse."); }
        else { MaximumHealth += 1; Health = Math.Min(MaximumHealth, Health + 2); Say("Vara opens the landing shutter. The lift carries a canvas sling lined with bandages. The crew gains one maximum vitality."); }
    }
    void EngageHand(int room)
    {
        if (HandsSet >= 2) return;
        if (room != NextDrum) { Say(room == 5 ? "Vara taps the gauge. Lio needs to brace his end first." : "Lio nods toward the drum. Let Vara take the load first."); return; }
        if (room == 5) { varaHolding = true; varaPost = Chamber(5); }
        else { lioHolding = true; lioPost = Chamber(6); }
        HandsSet++;
        if (HandsSet == 1) { Say(room == 5 ? "Vara sets her shoulder under the drum. Lio calls from the opposite gallery." : "Lio braces his boot against the bracket. Vara points to the free drum."); return; }
        Say("The second line is fast. Both crew take their stations.");
    }
    public void CallVara()
    {
        if (Phase != YardPhase.Approach) return;
        if (PassageStage == WorksStage.Transfer && Near(Chamber(7), 1.40f)) { OpenArchive(); return; }
        if (PassageStage == WorksStage.TwoHands && Near(Chamber(5), 1.40f)) { EngageHand(5); return; }
        if (PassageStage == WorksStage.KeyRoom && Works!.Mechanism == InnerWork.Counterpoise && Machinery == 1 && Near(MachinePoint(1), .90f))
        { varaHolding = true; varaPost = MachinePoint(1); Machinery++; Say("Vara counterbalances Lio. Stand on the third brass shoe and lower the latch."); }
    }
    void ReadArchive()
    {
        PassageStage = WorksStage.TwoHands; Say(Works!.Discovery); LineClock = 13;
    }
    void LeaveMachine()
    {
        PassageStage = WorksStage.Stairs; Plan.OpenDoor(8, 3); lioHolding = varaHolding = false; Say(Works!.Exit); LineClock = 9;
    }
    void WorksInteract()
    {
        if (PassageStage >= WorksStage.Archive && !KeepsakeTaken && Near(Chamber(9), 1.28f))
        {
            KeepsakeTaken = KeepsakeCarried = true; Plan.OpenDoor(9, 5);
            Say("The " + Works!.Alcove.Relic + " lies behind a loose panel. The other side opens on Vara’s drum. Carry it to the archive for a choice of fittings."); return;
        }
        if (KeepsakeCarried && Near(Chamber(4), 1.4f))
        { Say(Works!.Alcove.Note + "   1  Take a tempered blade   ·   2  Take a shorter reel"); LineClock = 13; return; }
        switch (PassageStage)
        {
            case WorksStage.Sentries when Foes.Count == 0 && Near(Chamber(2), 1.4f): OpenArchive(); break;
            case WorksStage.Archive when Near(Chamber(4), 1.45f): ReadArchive(); break;
            case WorksStage.TwoHands when Near(Chamber(4), 1.45f): Say(Works!.Discovery); LineClock = 13; break;
            case WorksStage.KeyRoom when Machinery >= 2:
                var release = Works!.Mechanism == InnerWork.Counterpoise ? MachinePoint(2) : Chamber(8);
                if (Near(release, .99f)) LeaveMachine();
                break;
            case WorksStage.Stairs when Near(Chamber(3), 1.45f):
                KeepsakeCarried = false; Works = null; GenerateDistrict(); break;
        }
    }
    bool ClaimKeepsake(int slot)
    {
        if (!KeepsakeCarried || !Near(Chamber(4), 1.4f) || slot is < 1 or > 2) return false;
        KeepsakeCarried = false; KeepsakeReturned = true;
        if (slot == 1) Edge = Math.Min(3, Edge + 1); else Quickline = Math.Min(3, Quickline + 1);
        Say(Works!.Alcove.Note); LineClock = 12; return true;
    }
    public IEnumerable<(Vector2 Position, string Label)> SideRooms()
    {
        if (PassageStage < WorksStage.Archive) yield break;
        if (!KeepsakeTaken) yield return (Chamber(9), "E  Search " + Works!.Alcove.Room);
        if (KeepsakeCarried) yield return (Chamber(4), "1  Blade  ·  2  Reel  ·  return " + Works!.Alcove.Relic);
    }
    bool WorksTurn(bool cut, bool hook)
    {
        void LineTo(Vector2 p) { Hook = .44f; HookWait = .80f; HookEnd = p; }
        if (PassageStage == WorksStage.Mouth)
        {
            if (hook && Near(Chamber(1), 1.55f))
            {
                lioHolding = true; lioPost = Chamber(1); LineTo(lioPost); Plan.OpenDoor(1, 7); PassageStage = WorksStage.Transfer;
                Say("Lio keeps the lift under tension. Cross to its far end and call Vara to the wheel with F."); return true;
            }
            if (cut && Near(Chamber(2), 1.45f)) { TookPit = true; SpawnWatch(Chamber(2), false); PassageStage = WorksStage.Sentries; Say("The seal splits. Two toll keepers move for the watch pass."); }
        }
        else if (PassageStage == WorksStage.TwoHands && hook && Near(Chamber(6), 1.55f))
        { LineTo(Chamber(6)); EngageHand(6); return true; }
        else if (PassageStage == WorksStage.KeyRoom && Machinery < 2)
        {
            var kind = Works!.Mechanism;
            var mark = MachinePoint(Machinery);
            if (kind == InnerWork.Casting)
            {
                if ((cut && Near(Forging, 1.25f)) || (hook && Near(Forging, 2.85f)))
                {
                    var aim = hook ? Player - Forging : Forging - Player;
                    if (hook) LineTo(Forging);
                    Forging = Plan.Patches[8].Closest(Forging + Unit(aim) * (hook ? .92f : .64f));
                    if (Vector2.DistanceSquared(Forging, MachinePoint(1)) < .64f) { Machinery = 2; Say("The shoe rings true. Take the key from the open die."); }
                    return hook;
                }
            }
            else if (kind == InnerWork.Floodgate && hook && Near(mark, 1.50f))
            { LineTo(mark); Machinery++; Say(Machinery == 1 ? "Water falls from the first float. The low side is reachable." : "Both floats are up. Open the valve between them."); return true; }
            else if (kind == InnerWork.Counterpoise && Machinery == 0 && hook && Near(mark, 1.30f))
            { LineTo(mark); lioPost = mark; lioHolding = true; Machinery++; Say("Lio hangs the first weight. Bring Vara to the opposite pan and signal F."); return true; }
            else if (kind == InnerWork.Loom && cut && Near(mark, 1.02f))
            { Machinery++; Say(Machinery == 1 ? "The first stay recoils. Cut the second from the other side." : "The tooth is free. Reach inside the escapement."); }
        }
        return false;
    }
    public IEnumerable<(Vector2 Position, string Label)> WorksGoals()
    {
        var w = Works!;
        switch (PassageStage)
        {
            case WorksStage.Mouth: yield return (Chamber(1), "K  " + w.SafeRoom + " · vitality"); yield return (Chamber(2), "J  " + w.RiskRoom + " · 3 chits"); break;
            case WorksStage.Transfer: yield return (Chamber(7), "F  Vara · turn lift wheel"); break;
            case WorksStage.Sentries: if (Foes.Count == 0) yield return (Chamber(2), "E  Take watch pass"); break;
            case WorksStage.Archive: yield return (Chamber(4), "E  Inspect " + w.Archive); break;
            case WorksStage.TwoHands when HandsSet == 2: yield return (Chamber(8), "Paired shutters · crew at work"); break;
            case WorksStage.TwoHands: yield return (Chamber(NextDrum), NextDrum == 5 ? "F  Vara · brace drum" : "K  Lio · hook bracket"); break;
            case WorksStage.KeyRoom:
                if (Machinery >= 2) { yield return (w.Mechanism == InnerWork.Counterpoise ? MachinePoint(2) : Chamber(8), "E  Release " + w.Key); break; }
                if (w.Mechanism == InnerWork.Casting) { yield return (Forging, "J  Push · K  pull shoe"); yield return (MachinePoint(1), "Casting bed"); }
                else yield return (MachinePoint(Machinery), w.Mechanism switch { InnerWork.Loom => Machinery == 0 ? "J  Cut first stay" : "J  Cut second stay", InnerWork.Floodgate => Machinery == 0 ? "K  Raise first float" : "K  Raise second float", _ => Machinery == 0 ? "K  Hang Lio’s weight" : "F  Call Vara to the pan" });
                break;
            case WorksStage.Stairs: yield return (Chamber(3), "E  Use " + w.Key + " · upper stair"); break;
        }
    }
    string WorksObjective => PassageStage switch
    {
        WorksStage.Mouth => "Take the crew lift or break into the pit",
        WorksStage.Transfer => "Cross the lift to Vara’s wheel",
        WorksStage.Sentries => Foes.Count > 0 ? "Defeat the watch and recover their pass" : "Take the watch pass",
        WorksStage.Archive => "Find the record behind the shutters",
        WorksStage.TwoHands when HandsSet == 2 => "Both crew are taking the load",
        WorksStage.TwoHands => NextDrum == 5 ? "Vara must hold the marked drum" : "Lio must brace the marked bracket",
        WorksStage.KeyRoom => Machinery >= 2 ? "Release the " + Works!.Key : "Operate the " + Works!.Apparatus,
        _ => "Unlock the stair to the surface"
    };
}
