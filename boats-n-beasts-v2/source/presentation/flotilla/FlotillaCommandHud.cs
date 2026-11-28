using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class FlotillaCommandHud : Control
{
    public FlotillaCommand Game = null!;
    readonly Font face = ThemeDB.FallbackFont;
    readonly Font serif = new SystemFont { FontNames = ["Baskerville", "Georgia"] };
    static readonly Color Ink = new("142e3d"), Cream = new("ffeac8"), Gold = new("efbe76"), Mint = new("97dcc7"), Red = new("fb8d78");
    FleetCommand Fleet => Game.Battle;
    Vector2 Screen(N p, float y = .20f) => Game.Sea.ElevatedScreen(p, y);
    void Word(string s, Vector2 p, int size, Color tone, float width = -1, bool heading = false) => DrawString(heading ? serif : face, p, s, HorizontalAlignment.Left, width, size, tone);
    void Box(Vector2 at, Vector2 size, Color line)
    { DrawRect(new(at, size), new Color(Ink, .94f)); DrawLine(at, at + Vector2.Right * size.X, line, 2); }
    void Tag(Vector2 at, string s, Color edge, int size = 15)
    { float w = face.GetStringSize(s, fontSize: size).X + 18; var p = at - new Vector2(w / 2, 21); Box(p, new(w, 26), edge); Word(s, p + new Vector2(9, 18), size, Cream); }
    public override void _Draw()
    {
        if (Game == null || Game.MenuUp || !Fleet.AtSea) return;
        if (Fleet.Pilot is { } pilot && Game.PilotView != null) { DrawPilot(pilot, Game.PilotView); return; }
        DrawWater();
        Box(new(22, 17), new(396, 76), Gold);
        Word(Fleet.Order.Region.ToUpperInvariant() + "    /    FLOTILLA COMMAND", new(36, 41), 14, Gold, 367);
        Word(Fleet.Field switch { FleetField.Rescue => "The broken ferry", FleetField.Passage => "The divided channel", FleetField.Captain => Fleet.Order.Boss, _ => Fleet.Haven }, new(36, 75), 25, Cream, 367, true);
        if (Game.Chart) Chart(); else Roster();
        float w = Math.Min(Size.X - 44, face.GetStringSize(Fleet.Objective, fontSize: 18).X + 34);
        Box(new((Size.X - w) / 2, Size.Y - 158), new(w, 35), Gold); Word(Fleet.Objective, new((Size.X - w) / 2 + 17, Size.Y - 134), 18, Cream, w - 25);
        string call = Fleet.Call;
        float v = Math.Min(Size.X - 44, face.GetStringSize(call, fontSize: 15).X + 30);
        Box(new((Size.X - v) / 2, Size.Y - 194), new(v, 31), Mint); Word(call, new((Size.X - v) / 2 + 15, Size.Y - 172), 15, Mint, v - 23);
        Box(new(22, Size.Y - 99), new(328, 73), Gold);
        Word($"Cutter {Fleet.Ship.Health:0}/{Fleet.Ship.MaxHealth:0}    ·    {Game.SilverAboard} silver", new(36, Size.Y - 67), 19, Cream);
        Word($"E   Repair ×{Fleet.Kits}     Shift   Surge {Fleet.Ship.Boost:0}%", new(36, Size.Y - 40), 15, Mint);
        Box(new(Size.X - 488, Size.Y - 99), new(466, 73), Gold);
        Word("1–3  Select hull      Tab  Next post      Q  Dispatch", new(Size.X - 473, Size.Y - 69), 18, Cream);
        Word("G  Work alongside    Space  Fire    R  Recall    M  Chart", new(Size.X - 473, Size.Y - 40), 15, Mint);
    }
    void DrawPilot(FleetPilot p, FlotillaCommandPilot view)
    {
        var dye = FlotillaCommandArt.Standards[(int)p.Role];
        if (p.Attached) BoardingLine.Draw(this, view.Screen(p.Position, .33f), view.Screen(p.Tow, .27f), .30f, true);
        if (p.Warning > 0 || p.Splash > 0)
        {
            Vector2[] ring = new Vector2[35]; for (int i = 0; i < ring.Length; i++) { float a = i * Mathf.Tau / 34; ring[i] = view.Screen(p.Shot + new N(MathF.Cos(a), MathF.Sin(a)) * 121, .22f); }
            DrawPolyline(ring, Red, p.Warning > 0 ? 3 : 6, true);
        }
        var projected = view.Screen(p.Goal, 1.1f);
        var pin = new Vector2(Math.Clamp(projected.X, 140, Size.X - 145), Math.Clamp(projected.Y, 145, Size.Y - 180));
        if (pin.X > Size.X - 264 && pin.Y < 190) pin.Y = 205;
        if (pin.DistanceTo(projected) > 48) DrawLine(pin, pin + (projected - pin).Normalized() * 29, dye, 3, true);
        Tag(pin, p.Label, dye, 16);
        string watchName = p.Company.ToUpperInvariant() + "    /    " + p.Skipper;
        float widthNeeded = Math.Max(364, Math.Min(526, face.GetStringSize(watchName, fontSize: 15).X + 32));
        Box(new(21, 18), new(widthNeeded, 77), dye); Word(watchName, new(35, 45), 15, dye, widthNeeded - 24);
        Word(p.Title, new(35, 77), 24, Cream, 339, true);
        float x = Size.X - 252; Box(new(x, 18), new(230, 151), dye); Word("Pilot’s plot", new(x + 12, 40), 14, Cream);
        Vector2 Plot(N at) => new(x + 115 + at.X * .091f, 96 + at.Y * .078f);
        foreach (var boom in p.Obstacles) DrawLine(Plot(boom.A), Plot(boom.B), Gold, 4, true);
        foreach (var mark in p.Marks()) DrawCircle(Plot(mark.Position), 3, new Color(Mint, .70f));
        DrawArc(Plot(p.Goal), 7, 0, Mathf.Tau, 14, Gold, 2, true); DrawCircle(Plot(p.Position), 4, dye);
        if (p.Attached) DrawLine(Plot(p.Position), Plot(p.Tow), Cream, 2, true);
        string action = p.Role switch { FleetRole.Tug => "Shift  Brake    Space  Winch", FleetRole.Sloop => "Shift  Run before wind    Space  Fire", _ => "Shift  Pull hard    Space  Cut sail" };
        Box(new(21, Size.Y - 92), new(335, 66), dye); Word($"Working hull {p.Integrity:0}/{p.Maximum:0}   ·   {Fleet.Silver} silver", new(34, Size.Y - 66), 18, Cream);
        Word($"Q  Cover ×{p.Support}    E  Patch ×{Fleet.Kits}", new(34, Size.Y - 40), 15, Mint);
        Box(new(Size.X - 389, Size.Y - 92), new(366, 66), dye); Word("WASD  Helm     G  Work alongside", new(Size.X - 375, Size.Y - 66), 18, Cream);
        Word(action, new(Size.X - 375, Size.Y - 40), 15, Mint);
        float width = Math.Min(Size.X - 44, face.GetStringSize(p.Instructions, fontSize: 17).X + 30);
        Box(new((Size.X - width) / 2, Size.Y - 137), new(width, 32), Gold);
        Word(p.Instructions, new((Size.X - width) / 2 + 15, Size.Y - 115), 17, Cream, width - 22);
    }
    void Roster()
    {
        float x = Size.X - 324, y = 18;
        for (int i = 0; i < 3; i++)
        {
            var a = Fleet.Allies[i]; var color = FlotillaCommandArt.Standards[i];
            Box(new(x, y), new(302, 57), i == Fleet.Selected ? Gold : color);
            if (i == Fleet.Selected) DrawRect(new(x, y, 4, 57), Gold);
            Word($"{i + 1}   {a.Name}   {a.Hull:0}/{a.Maximum:0}", new(x + 13, y + 23), 17, a.Afloat ? Cream : Red, 278);
            Word(Fleet.Duty(a), new(x + 13, y + 47), 14, color, 270); y += 62;
        }
    }
    void DrawWater()
    {
        foreach (var lane in Fleet.Lanes)
        {
            var rim = Outline(lane);
            var color = lane.Strike is FleetStrike.Ice or FleetStrike.Nets ? new Color("adabf2") : Red;
            DrawColoredPolygon(rim, new Color(color, lane.Fired ? .45f : .19f));
            DrawPolyline([.. rim, rim[0]], new Color(color, lane.Fired ? .96f : .83f), lane.Fired ? 4 : 2, true);
        }
        if (Fleet.LeadOn) BoardingLine.Draw(this, Screen(Fleet.Ship.Position, .36f), Screen(Fleet.LeadEnd, .35f), .35f, true);
        if (Fleet.Clouds)
        {
            DrawPolyline(Ring(Fleet.Fog, Fleet.FogWidth), new Color(Mint, .50f), 2, true);
            var decoy = Screen(Fleet.Decoy, 2.12f);
            if (!Fleet.FalseLight && OnScreen(decoy)) Tag(decoy, Fleet.NamedSignal ? "Borrowed flag" : "Second pennant", Gold, 14);
        }
        foreach (var a in Fleet.Allies)
        {
            var dye = FlotillaCommandArt.Standards[(int)a.Role];
            var mid = Screen(a.Position, .20f);
            if (a.Guard > 0) DrawPolyline(Ring(a.Position, Fleet.ShieldRange(a)), new Color(dye, .7f), 2, true);
            if (a.Signals > 2.8f) DrawArc(mid, 19 + (a.Signals % 1) * 28, 0, Mathf.Tau, 28, new Color(dye, .67f), 2, true);
            if (a.Assignment >= 0 && a.Assignment < Fleet.Stations.Count)
            {
                var s = Fleet.Stations[a.Assignment];
                if (s.Task == FleetTask.Ferry && s.Work >= 1 && N.DistanceSquared(a.Position, s.Position) < 249 * 249)
                    BoardingLine.Draw(this, Screen(a.Position, .38f), Screen(s.Position, .30f), .22f, true);
            }
            if (!OnScreen(mid)) continue;
            var mark = Screen(a.Position, 1.81f);
            if ((int)a.Role == Fleet.Selected) { DrawPolyline(Ring(a.Position, 87), new Color(dye, .95f), 2, true); Tag(mark, $"{(int)a.Role + 1}   {a.Name}", dye); }
            else { DrawCircle(mark, 11, Ink); Word(((int)a.Role + 1).ToString(), mark + new Vector2(-4, 5), 14, dye); }
        }
        foreach (var station in Fleet.Stations)
        {
            if (station.Done) continue;
            var post = Screen(station.Position, .24f);
            if (station.Task == FleetTask.Ferry)
            {
                DrawPolyline(Ring(station.Berth, 115), new Color(Mint, .82f), 3, true);
                if (N.DistanceSquared(station.Berth, station.Position) > 195 * 195 && OnScreen(Screen(station.Berth, .8f))) Tag(Screen(station.Berth, .8f), "Receiving gate", Mint, 13);
            }
            if (!OnScreen(post) || station == Fleet.Stations[Fleet.Post]) continue;
            DrawArc(post, 13, 0, Mathf.Tau, 18, Gold, 2, true);
        }
        if (Fleet.EnemyVisible)
        {
            var captain = Screen(Fleet.EnemyHull, 2.7f);
            if (OnScreen(captain)) Tag(captain, Fleet.GunsDown == 2 ? $"{Fleet.Order.Boss}  ·  {Fleet.EnemyStrength:0} rig" : Fleet.Order.Boss, Red, 16);
        }
        var hands = Fleet.HandsPoint;
        var g = Screen(hands, 1.05f);
        var hpin = new Vector2(Math.Clamp(g.X, 155, Size.X - 145), Math.Clamp(g.Y, 140, Size.Y - 270));
        if (!Game.Chart && hpin.X > Size.X - 323 && hpin.Y < 218) hpin.Y = 245;
        if (hpin.DistanceTo(g) > 40) DrawLine(hpin, hpin + (g - hpin).Normalized() * 26, Mint, 3, true);
        if (Fleet.Field != FleetField.Refuge || Fleet.HomeGate < 2) Tag(hpin, "G   " + Fleet.HandsLabel, Mint, 15);
        var goal = Fleet.Destination;
        var projected = Screen(goal, 1.55f);
        var pin = new Vector2(Math.Clamp(projected.X, 108, Size.X - 117), Math.Clamp(projected.Y, 133, Size.Y - 226));
        if (!Game.Chart && pin.X > Size.X - 326 && pin.Y < 210) pin.Y = 215;
        if (pin.DistanceTo(projected) > 48) DrawLine(pin, pin + (projected - pin).Normalized() * 28, Gold, 3, true);
        var delta = goal - Fleet.Ship.Position;
        string[] compass = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"];
        string bearing = compass[((int)MathF.Round(MathF.Atan2(delta.Y, delta.X) / (MathF.PI / 4)) + 8) % 8];
        if (pin.DistanceTo(hpin) < 165) pin.Y -= 35;
        Tag(pin, $"{Fleet.TaskName}   {bearing} {MathF.Ceiling(delta.Length() / 100):0}", Gold, 16);
    }
    bool OnScreen(Vector2 p) => p.X > 20 && p.X < Size.X - 20 && p.Y > 105 && p.Y < Size.Y - 202;
    Vector2[] Ring(N center, float r)
    {
        Vector2[] pts = new Vector2[35];
        for (int i = 0; i < pts.Length; i++) { float a = i * Mathf.Tau / 34; pts[i] = Screen(center + new N(MathF.Cos(a), MathF.Sin(a)) * r); }
        return pts;
    }
    Vector2[] Outline(FleetLane lane)
    {
        if (N.DistanceSquared(lane.From, lane.To) < 1) return Ring(lane.To, lane.Width)[..^1];
        float a = MathF.Atan2(lane.To.Y - lane.From.Y, lane.To.X - lane.From.X);
        Vector2[] pts = new Vector2[22];
        for (int i = 0; i < 11; i++)
        {
            float front = a - MathF.PI / 2 + i * MathF.PI / 10, back = front + MathF.PI;
            pts[i] = Screen(lane.To + new N(MathF.Cos(front), MathF.Sin(front)) * lane.Width);
            pts[11 + i] = Screen(lane.From + new N(MathF.Cos(back), MathF.Sin(back)) * lane.Width);
        }
        return pts;
    }
    void Chart()
    {
        var pos = new Vector2(Size.X - 430, 18); var dimensions = new Vector2(408, 240); Box(pos, dimensions, Gold);
        Word("OFFICER’S PLOT", pos + new Vector2(13, 25), 14, Gold);
        var points = Fleet.Stations.Where(p => !p.Done).Select(p => p.Position).Concat(Fleet.Allies.Select(a => a.Position)).Append(Fleet.Ship.Position).ToArray();
        float minX = points.Min(p => p.X), minY = points.Min(p => p.Y), maxX = points.Max(p => p.X), maxY = points.Max(p => p.Y);
        float scale = Math.Min(350 / Math.Max(450, maxX - minX), 158 / Math.Max(400, maxY - minY));
        var center = new N((maxX + minX) / 2, (maxY + minY) / 2);
        Vector2 Dot(N p) => pos + new Vector2(201 + (p.X - center.X) * scale, 124 + (p.Y - center.Y) * scale);
        foreach (var lane in Fleet.Lanes) DrawLine(Dot(lane.From), Dot(lane.To) + Vector2.Right, Red, Math.Max(3, lane.Width * scale), true);
        for (int i = 0; i < Fleet.Stations.Count; i++)
        {
            var p = Fleet.Stations[i]; if (p.Done) continue; var at = Dot(p.Position);
            DrawArc(at, i == Fleet.Post ? 10 : 6, 0, Mathf.Tau, 16, Gold, i == Fleet.Post ? 3 : 1, true);
            if (p.Task == FleetTask.Ferry) DrawLine(at, Dot(p.Berth), Mint, 1.5f, true);
        }
        for (int i = 0; i < 3; i++)
        {
            var a = Fleet.Allies[i]; var pin = Dot(a.Position); var dye = FlotillaCommandArt.Standards[i];
            if (a.Assignment >= 0) DrawLine(pin, Dot(Fleet.Stations[a.Assignment].Position), new Color(dye, .64f), 2, true);
            DrawCircle(pin, 7, dye); Word((i + 1).ToString(), pin + new Vector2(6, -5), 14, dye);
        }
        DrawCircle(Dot(Fleet.Ship.Position), 5, Cream);
        var hands = Dot(Fleet.HandsPoint); DrawArc(hands, 9, 0, Mathf.Tau, 20, Mint, 2, true); Word("G", hands + new Vector2(9, 4), 14, Mint);
        Word($"{Fleet.Allies[Fleet.Selected].Name}   →   {Fleet.TaskName}", pos + new Vector2(13, 222), 15, Mint, 382);
    }
}
