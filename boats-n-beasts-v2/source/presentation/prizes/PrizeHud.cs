using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class PrizeHud : Control
{
    public PrizeWatch Game = null!;
    readonly Font face = ThemeDB.FallbackFont;
    readonly Font serif = new SystemFont { FontNames = ["Baskerville", "Georgia"] };
    static readonly Color Ink = new("162d3a"), Cream = new("ffebbd"), Gold = new("e6b274"), Mint = new("8fe2c6"), Red = new("ff9375");
    void Box(Vector2 at, Vector2 size, Color edge) { DrawRect(new(at, size), new Color(Ink, .94f)); DrawLine(at, at + Vector2.Right * size.X, edge, 2); }
    void Word(string s, Vector2 at, int px, Color color, bool title = false) => DrawString(title ? serif : face, at, s, HorizontalAlignment.Left, -1, px, color);
    public override void _Draw()
    {
        if (Game == null || Game.MenuUp || Game.Child != null) return;
        var watch = Game.Watch;
        Box(new(20, 16), new(374, 78), Gold);
        Word($"{watch.RegionName.ToUpperInvariant()}   ·   PRIZE WATCH {Math.Min(watch.Index + 1, watch.Operations.Length)}/{watch.Operations.Length}", new(34, 43), 14, Gold);
        Word(Game.Board?.RoomName ?? watch.WatchName, new(34, 75), 23, Cream, true);
        if (Game.Board is { } boarding) DrawBoard(boarding); else DrawSea(watch);
    }
    void DrawSea(PrizeTheater w)
    {
        var s = w.Ship; var sea = Game.Sea;
        if (w.Phase is PrizePhase.Search or PrizePhase.Chase)
        {
            for (int i = 0; i < w.Contacts.Length; i++)
            {
                var c = w.Contacts[i]; if (c.Released) continue;
                var p = sea.ElevatedScreen(c.Position, 1.36f);
                if (!Safe(p, 55) || N.DistanceSquared(s.Position, c.Position) > 680 * 680) continue;
                string name = c.Name + "   ·   " + (c.Inspected ? PrizeTheater.Seals[c.Stamp] : PrizeTheater.Rigs[c.Rig]);
                Tag(p, name, PrizeArt.Flag(c.Color), 14);
                if (N.DistanceSquared(s.Position, c.Position) < 196 * 196) Tag(p + Vector2.Down * 27, "Q   Read hull stamp", Mint, 13);
            }
        }
        if (!w.Foraged && w.Phase != PrizePhase.Return && N.DistanceSquared(s.Position, w.Cache) < 685 * 685)
        {
            var p = sea.ElevatedScreen(w.Cache, 1);
            if (Safe(p, 65)) Tag(p, "Q   Pilot’s canvas cache", Mint, 14);
        }
        if (w.HasFinalTow)
        {
            BoardingLine.Draw(this, sea.ElevatedScreen(s.Position, .26f), sea.ElevatedScreen(w.Tow, .24f), .35f, true);
            var tender = sea.ElevatedScreen(w.Tow, .55f); Tag(tender, $"Prize hull {w.TowHull:0}%", Mint, 13);
        }
        if (w.HookFlash > 0) BoardingLine.Draw(this, sea.ElevatedScreen(s.Position, .40f), sea.ElevatedScreen(w.HookEnd, .38f), .43f, false);
        if (w.Phase == PrizePhase.Inquiry && w.Inquiry is { } field)
        {
            foreach (var site in field.Sites())
            {
                var sp = sea.ElevatedScreen(site.Point, .86f);
                if (Safe(sp, 55) && N.DistanceSquared(site.Point, field.Goal) > 80 * 80) Tag(sp, site.Label, Mint, 14);
            }
            if (field.Kind == InquiryKind.Soundings && field.Step == InquiryStep.Purchase)
                BoardingLine.Draw(this, sea.ElevatedScreen(field.Diver, .25f), sea.ElevatedScreen(field.Windlass, .25f), .25f, true);
            if (field.HasPilot) BoardingLine.Draw(this, sea.ElevatedScreen(s.Position, .3f), sea.ElevatedScreen(field.Lead, .3f), .3f, true);
            if (field.RivalOn)
            {
                var rp = sea.ElevatedScreen(field.Rival, 1.26f);
                if (Safe(rp, 55)) Tag(rp, $"{field.RivalName}    {field.RivalGear:0} rig", Red, 14);
                if (field.LampVisible)
                {
                    var start = field.Rival;
                    float angle = MathF.Atan2(field.ShadowBow.Y, field.ShadowBow.X);
                    var cone = new Vector2[13]; cone[0] = sea.ElevatedScreen(start, .30f);
                    for (int i = 1; i < cone.Length; i++) { float a = angle - .35f + (i - 1) * .70f / (cone.Length - 2); cone[i] = sea.ElevatedScreen(start + new N(MathF.Cos(a), MathF.Sin(a)) * field.LightRadius, .30f); }
                    DrawColoredPolygon(cone, new Color(Gold, .21f)); DrawPolyline([.. cone, cone[0]], Gold, 2, true);
                }
            }
        }
        if (w.Phase == PrizePhase.Assize && w.Assize is { } court)
        {
            foreach (var site in court.Sites())
            {
                var at = sea.ElevatedScreen(site.Point, 1.23f);
                if (Safe(at, 60) && N.DistanceSquared(site.Point, court.Goal) > 95 * 95) Tag(at, site.Label, site.Kind == "picket" ? Red : Mint, 14);
            }
            if (court.WindUp > 0)
            {
                var warn = sea.ElevatedScreen(court.SlashTo, .35f);
                if (court.Move == CourtManeuver.Ram) DrawLine(sea.ElevatedScreen(court.SlashFrom, .35f), warn, new Color(Red, .65f), 10, true);
                Vector2[] rim = new Vector2[41];
                for (int i = 0; i < rim.Length; i++)
                { float a = i * Mathf.Tau / 40; rim[i] = sea.ElevatedScreen(court.SlashTo + new N(MathF.Cos(a), MathF.Sin(a)) * court.Radius, .36f); }
                DrawPolyline(rim, Red, 3, true);
            }
        }
        var goal = w.Destination;
        string label = w.Phase switch { PrizePhase.Witness => "Packet boat", PrizePhase.Inquiry => w.Inquiry!.BearingName, PrizePhase.Assize => w.Assize!.Label, PrizePhase.Search => w.Contacts[w.ContactCursor].Name, PrizePhase.Chase => "Suspect’s rigging", PrizePhase.Return => w.ReturnGate < w.Gates.Length ? "Pilot gate" : "Recovery tender", _ => "Watch roads" };
        float height = w.Phase == PrizePhase.Assize && w.Assize != null && goal == w.Assize.Bench ? 2.75f : 1.56f;
        Waypoint(sea.ElevatedScreen(goal, height), label, goal - s.Position);
        if (w.Report > 0 && w.Phase is PrizePhase.Search or PrizePhase.Chase)
        {
            string clue = $"Seek {PrizeTheater.Flags[w.Mark.Color]} cloth · {PrizeTheater.Rigs[w.Mark.Rig]} · {PrizeTheater.Seals[w.Mark.Stamp]}";
            Box(new(20, 99), new(Math.Max(374, face.GetStringSize(clue, fontSize: 15).X + 25), 33), Mint);
            Word(clue, new(33, 122), 15, Mint);
        }
        Box(new(20, Size.Y - 87), new(315, 65), Gold);
        Word($"Hull {s.Health:0} / {s.MaxHealth:0}     {Game.SilverEarned} silver", new(34, Size.Y - 60), 18, Cream);
        Word($"E  Patch ×{w.Kits}    ·    Shift  Surge {s.Boost:0}%    ·    Alarm {w.Alarm}", new(34, Size.Y - 35), 14, Mint);
        Box(new(Size.X - 366, Size.Y - 87), new(346, 65), Gold);
        Word("WASD   Helm      Space / click   Guns", new(Size.X - 352, Size.Y - 61), 17, Cream);
        Word(w.Phase == PrizePhase.Inquiry ? $"Q   Work     X   Ally ×{w.Allies}   Tab   Branch   M   Log" : "Q   Hail / line     Tab   Next sail     M   Log", new(Size.X - 352, Size.Y - 36), 15, Mint);
        Message(w.Instructions, w.DispatchTime > 0 ? w.Dispatch : "");
    }
    void DrawBoard(PrizeBoarding b)
    {
        var deck = Game.Deck!; var at = deck.Screen(b.Player);
        foreach (var g in b.Guards)
        {
            if (g.Health <= 0) continue;
            var p = deck.Screen(g.Position, .47f);
            if (g.Stun > 0) DrawArc(p, 16, 0, Mathf.Tau, 16, Mint, 3, true);
            if (g.Tell > 0)
            {
                if (g.Role == 2 || g.Role == 1 || g.Role == 3 && !g.Rim)
                {
                    var side = new N(-g.Aim.Y, g.Aim.X) * .40f; var end = g.Position + g.Aim * (g.Role == 2 ? 5.0f : 2.36f);
                    Vector2[] points = [deck.Screen(g.Position - side), deck.Screen(g.Position + side), deck.Screen(end + side), deck.Screen(end - side)];
                    DrawColoredPolygon(points, new Color(Red, .35f)); DrawPolyline([.. points, points[0]], Red, 2, true);
                }
                else DrawPolyline(Loop(g.Position, g.Role == 3 ? 1.9f : 1.13f), Red, 4, true);
            }
            var health = deck.Screen(g.Position, 1.55f);
            DrawRect(new(health + new Vector2(-15, -2), new(30, 4)), Ink);
            DrawRect(new(health + new Vector2(-15, -2), new(30f * g.Health / g.MaxHealth, 4)), Red);
        }
        if (b.Swing > 0)
        {
            Vector2[] arc = new Vector2[13]; float a = MathF.Atan2(b.Facing.Y, b.Facing.X);
            for (int i = 0; i < arc.Length; i++) { float t = a - 1.08f + i * .18f; arc[i] = deck.Screen(b.Player + new N(MathF.Cos(t), MathF.Sin(t)) * 1.35f, .70f); }
            DrawPolyline(arc, Cream, 5, true);
        }
        if (b.Rope > 0) BoardingLine.Draw(this, deck.Screen(b.Mate, 1.0f), deck.Screen(b.HookEnd, .85f), .25f, true);
        if (b.Examining)
        {
            for (int i = 0; i < 3; i++)
                Tag(deck.Screen(b.BenchPoints[i], .96f), b.BenchNames[i], i == b.Examination - 1 ? Mint : Gold, 14);
        }
        if (!b.Fixed && b.Work == DeckWork.Search && !b.Examining)
            for (int i = 0; i < b.Lockers.Length; i++) Tag(deck.Screen(b.Lockers[i], 1.13f), PrizeTheater.Seals[i], Gold, 14);
        if (!b.Looted) Tag(deck.Screen(b.Stash, 1.0f), "E  Dressing", Mint, 13);
        if (b.Fixed)
        {
            Tag(deck.Screen(b.Hatch, .85f), b.Room == b.Rooms ? "E  Back to cutter" : "E  Covered hatch", Mint, 15);
            Tag(deck.Screen(b.Ladder, .97f), b.Room == b.Rooms ? "E  Back to cutter" : "E  Prize ladder", Gold, 15);
        }
        else if (b.Work != DeckWork.Search)
        {
            var loc = b.Objective; Tag(deck.Screen(loc, 1.12f), b.Work == DeckWork.Captain ? "Quartermaster" : b.RequiresBrace && !b.MateAtBrake ? "Q  Brace the brake" : b.PassengerFree ? "E  Launch rail" : "E  Work station", Gold, 15);
        }
        if (b.MateAtBrake) DrawPolyline(Loop(b.Hitch, .49f), Mint, 2, true);
        Box(new(20, Size.Y - 87), new(298, 65), Gold);
        Word($"Crew {b.Health}/{b.MaxHealth}     {Game.SilverEarned} silver", new(34, Size.Y - 60), 18, Cream);
        Word($"Room {b.Room} of {b.Rooms}    ·    R  Dressing ×{b.Salves}", new(34, Size.Y - 35), 15, Mint);
        Box(new(Size.X - 370, Size.Y - 87), new(350, 65), Gold);
        Word("WASD  Move      Space / J  Strike      Shift  Roll", new(Size.X - 358, Size.Y - 61), 15, Cream);
        Word("Q  Command Lio      E  Work / open / leave", new(Size.X - 358, Size.Y - 36), 15, Mint);
        Message(b.Instruction, b.Call);
    }
    Vector2[] Loop(N p, float r)
    {
        Vector2[] ring = new Vector2[31]; for (int i = 0; i < ring.Length; i++) { float a = i * Mathf.Tau / 30; ring[i] = Game.Deck!.Screen(p + new N(MathF.Cos(a), MathF.Sin(a)) * r); }
        return ring;
    }
    bool Safe(Vector2 p, float margin) => p.X > margin && p.X < Size.X - margin && p.Y > 106 && p.Y < Size.Y - 190;
    void Waypoint(Vector2 screen, string title, N delta)
    {
        int distance = (int)MathF.Ceiling(delta.Length() / 100);
        string[] compass = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"];
        string bearing = compass[((int)MathF.Round(MathF.Atan2(delta.Y, delta.X) / (MathF.PI / 4)) + 8) % 8];
        var pin = new Vector2(Math.Clamp(screen.X, 115, Size.X - 115), Math.Clamp(screen.Y, 159, Size.Y - 222));
        if ((pin - screen).Length() > 52) DrawLine(pin, pin + (screen - pin).Normalized() * 34, Gold, 4, true);
        Tag(pin, title + $"   {bearing}  {distance}", Gold, 17);
    }
    void Tag(Vector2 at, string title, Color edge, int font)
    {
        float w = face.GetStringSize(title, fontSize: font).X + 20; Box(at - new Vector2(w / 2, 21), new(w, 26), edge); Word(title, at - new Vector2(w / 2 - 10, 2), font, Cream);
    }
    void Message(string objective, string crew)
    {
        float w = Math.Min(Size.X - 48, face.GetStringSize(objective, fontSize: 17).X + 32);
        Box(new((Size.X - w) / 2, Size.Y - 136), new(w, 34), Gold); Word(objective, new((Size.X - w) / 2 + 16, Size.Y - 113), 17, Cream);
        if (crew != "" && crew != objective) { float n = Math.Min(Size.X - 48, face.GetStringSize(crew, fontSize: 15).X + 30); Box(new((Size.X - n) / 2, Size.Y - 177), new(n, 30), Mint); Word(crew, new((Size.X - n) / 2 + 15, Size.Y - 156), 15, Mint); }
    }
}
