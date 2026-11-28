using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class YardHud : Control
{
    public KilnExpedition Trip = null!;
    Font font = null!;
    static readonly Color Deep = new("122e39ee"), Parchment = new("fff1d2"), Gold = new("f0c581"), Mint = new("92dfbf");
    public override void _Ready() { MouseFilter = MouseFilterEnum.Ignore; font = ThemeDB.FallbackFont; }
    public override void _Draw()
    {
        var y = Trip.Yard; var w = Size.X; var h = Size.Y;
        if (Trip.ChartOpen) { Chart(); return; }
        Box(new(22, 20, 530, 107));
        Text(40, 47, $"{(y.Order.Island.Length > 0 ? y.Order.Island : y.Order.Region).ToUpperInvariant()}    ·    {y.District + 1} / {y.LegCount}", 17, Gold);
        Text(40, 78, y.DistrictName, 25, Parchment); Text(40, 109, y.Objective, 19, Mint);
        if (y.Foes.FirstOrDefault(f => f.Kind == YardBeast.Guardian) is { } boss)
        {
            Box(new(w - 370, 20, 348, 71)); Text(w - 352, 49, y.Order.Boss.ToUpperInvariant(), 20, Gold);
            DrawRect(new(w - 351, 62, 306, 10), new("603f46"));
            DrawRect(new(w - 351, 62, 306f * boss.Health / boss.Maximum, 10), new("f18864"));
        }
        if (y.CanTrade)
        {
            Box(new(22, 138, 414, 145)); Text(39, 165, $"TRADE TARP   ·   {y.Chits} chits", 17, Gold);
            Text(39, 192, y.RationTaken ? "1   Rations served" : "1   Hot ration  +5 vitality   ·   1 chit", 18, Parchment);
            Text(39, 217, $"2   Temper blade  {y.Edge}/3   ·   2 chits", 18, Parchment);
            Text(39, 242, $"3   Shorten hook reel  {y.Quickline}/3   ·   2 chits", 18, Parchment);
            Text(39, 267, y.District + 2 < y.LegCount ? "4   Charter bypass  ·  4 chits" : "Last ferry takes the marked gate", 17, Mint);
        }
        if (y.AtStores)
        {
            Box(new(22, 140, 412, 93)); Text(39, 166, "SUPPLY CACHE", 18, Gold);
            Text(39, 194, "1   Take the ration   ·   3 vitality", 18, Parchment); Text(39, 219, "2   Take the pouch   ·   2 chits", 18, Parchment);
        }
        var labels = Trip.Locations().ToArray();
        for (int i = 0; i < labels.Length; i++) Beacon(labels[i].Position, labels[i].Name, i, labels.Length);
        foreach (var b in y.Foes.Where(f => f.Kind != YardBeast.Guardian))
        {
            var at = Trip.Stage.Lens.UnprojectPosition(Trip.Point(b.Position, 1.18f));
            DrawRect(new(at.X - 20, at.Y, 40, 5), Deep); DrawRect(new(at.X - 20, at.Y, 40f * b.Health / b.Maximum, 5), Gold);
        }
        Box(new(22, h - 58, 466, 40));
        Text(39, h - 32, $"Vitality   {y.Health}/{y.MaximumHealth}       {y.Silver} silver       {y.Chits} chits", 18, Mint);
        string controls = $"WASD  Move    J  Cut    K  {(y.HookWait > 0 ? $"Hook {y.HookWait:0.0}s" : "Hook")}    Space  Dodge    {(y.Works != null ? "F  Vara    " : "")}E  Work    M  Chart";
        float controlsWidth = font.GetStringSize(controls, fontSize: 18).X + 28;
        Box(new(w - 22 - controlsWidth, h - 58, controlsWidth, 40));
        Text(w - 8 - controlsWidth, h - 32, controls, 18, Parchment);
        if (y.LineClock > 0 && y.Phase != YardPhase.Lost)
        {
            const float max = 940;
            float width = Math.Min(max, font.GetStringSize(y.Line, fontSize: 19).X + 32);
            var measured = font.GetMultilineStringSize(y.Line, HorizontalAlignment.Center, width - 28, 19);
            float height = measured.Y + 13;
            Box(new((w - width) / 2, h - 78 - height, width, height));
            DrawMultilineString(font, new((w - width) / 2 + 14, h - 77 - height + 20), y.Line, HorizontalAlignment.Center, width - 28, 19, -1, Parchment);
        }
        if (y.Phase == YardPhase.Lost)
        {
            DrawRect(new(0, 0, w, h), new Color("0e2433bd"));
            DrawString(font, new(0, h * .45f), "The crew rows for home", HorizontalAlignment.Center, w, 38, Parchment);
            DrawString(font, new(0, h * .45f + 53), $"E   Return with {Trip.CarriedSilver + y.Silver} silver", HorizontalAlignment.Center, w, 22, Gold);
        }
    }
    void Chart()
    {
        var y = Trip.Yard; var plan = y.Plan; float w = Size.X, h = Size.Y;
        DrawRect(new(0, 0, w, h), new Color("102b37ed"));
        Box(new(w * .08f, h * .075f, w * .84f, h * .84f));
        Text(w * .11f, h * .141f, y.DistrictName, 33, Parchment);
        Text(w * .11f, h * .184f, (y.Order.Island.Length > 0 ? y.Order.Island : y.Order.Region) + "   ·   " + y.Objective, 19, Gold);
        var vertices = plan.Patches.SelectMany(p => p.Rim).ToArray();
        var lo = new System.Numerics.Vector2(vertices.Min(p => p.X), vertices.Min(p => p.Y));
        var hi = new System.Numerics.Vector2(vertices.Max(p => p.X), vertices.Max(p => p.Y));
        float scale = Math.Min(w * .68f / (hi.X - lo.X), h * .51f / (hi.Y - lo.Y));
        Vector2 P(System.Numerics.Vector2 at) => new(w * .5f + (at.X - (lo.X + hi.X) * .5f) * scale, h * .50f + (at.Y - (lo.Y + hi.Y) * .5f) * scale);
        for (int i = 0; i < plan.Passages.Length; i++)
        {
            var lane = plan.Passages[i]; var a = P(lane.From); var b = P(lane.To);
            if (i == plan.BrokenBridge || plan.GateClosed(i))
            {
                DrawLine(a, a.Lerp(b, .34f), Gold, 5); DrawLine(a.Lerp(b, .66f), b, Gold, 5);
                var mid = (a + b) * .5f; DrawLine(mid - new Vector2(4, 4), mid + new Vector2(4, 4), new("ef8b74"), 3); DrawLine(mid - new Vector2(-4, 4), mid + new Vector2(-4, 4), new("ef8b74"), 3);
            }
            else DrawLine(a, b, new Color("aca38b"), 6);
        }
        for (int i = 0; i < plan.Patches.Length; i++)
        {
            var patch = plan.Patches[i]; var points = patch.Rim.Select(P).ToArray();
            DrawColoredPolygon(points, new Color(y.Region.Ground).Darkened(.27f));
            DrawPolyline([.. points, points[0]], new("ceb993"), 1.4f, true);
            if (i > 5 && y.Works == null) continue;
            string label = y.Works != null ? patch.Name : i switch { 0 => "Landing", 1 => y.JobTitle(y.Options[0]), 2 => y.JobTitle(y.Options[1]), 3 => "Gate and trade", 4 => "Weigh house", _ => "Workers’ hall" };
            var pos = P(patch.Center); float width = font.GetStringSize(label, fontSize: 15).X + 13;
            DrawRect(new(pos.X - width / 2, pos.Y - 10, width, 22), Deep); Text(pos.X - width / 2 + 6, pos.Y + 6, label, 15, Parchment);
        }
        var goals = Trip.Locations().ToArray();
        if (goals.Length > 0)
        {
            var destination = goals[Trip.ChartTarget % goals.Length]; var from = y.Player;
            for (int i = 0; i < 18; i++)
            {
                var waypoint = plan.Waypoint(from, destination.Position);
                if (System.Numerics.Vector2.DistanceSquared(from, waypoint) < .006f) break;
                DrawDashedLine(P(from), P(waypoint), new("f8d48a"), 2.6f, 7);
                if (System.Numerics.Vector2.DistanceSquared(waypoint, destination.Position) < .05f) break;
                from = waypoint;
            }
            Text(w * .11f, h * .81f, "Tab   Plot course  ·  " + destination.Name, 18, Gold);
        }
        foreach (var spot in goals)
        {
            var p = P(spot.Position); DrawCircle(p, 6, Gold); DrawArc(p, 8, 0, Mathf.Tau, 20, Gold, 1.5f, true);
        }
        var here = P(y.Player); DrawCircle(here, 7, Mint); DrawArc(here, 11, 0, Mathf.Tau, 24, Mint, 2, true);
        Text(w * .11f, h * .86f, "Green   Crew       Gold   Work       Cross   Closed passage", 18, Mint);
        Text(w * .75f, h * .86f, "M   Close chart", 18, Parchment);
    }
    void Beacon(System.Numerics.Vector2 p, string name, int index, int count)
    {
        var at = Trip.Stage.Lens.UnprojectPosition(Trip.Point(p, .93f));
        float width = font.GetStringSize(name, fontSize: 16).X + 24;
        var pos = at.Clamp(new Vector2(width / 2 + 20, 157), new Vector2(Size.X - width / 2 - 20, Size.Y - 169));
        bool outside = at.DistanceSquaredTo(pos) > 2;
        if (outside && pos.Y == 157 && count > 1) pos.X = Mathf.Clamp(pos.X, Size.X * (index + .40f) / (count + .25f) - width * .3f, Size.X * (index + .60f) / (count + .25f) + width * .3f);
        Box(new(pos.X - width / 2, pos.Y - 14, width, 28)); Text(pos.X - width / 2 + 12, pos.Y + 6, name, 16, Gold);
        if (outside)
        {
            var dir = (at - pos).Normalized(); var side = new Vector2(-dir.Y, dir.X) * 4;
            var origin = pos + dir * (Math.Abs(dir.X) * width * .5f + 14);
            DrawColoredPolygon([origin + dir * 9, origin - side, origin + side], Gold);
        }
    }
    void Box(Rect2 r) { DrawRect(r, Deep); DrawLine(r.Position, r.Position + new Vector2(r.Size.X, 0), Gold, 1.5f); }
    void Text(float x, float y, string s, int size, Color tone) => DrawString(font, new(x, y), s, HorizontalAlignment.Left, -1, size, tone);
}
