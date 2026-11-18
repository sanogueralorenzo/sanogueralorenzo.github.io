using BoatsNBeasts.Core;
using Godot;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

internal readonly record struct ChartOrder(V2 Point, Beacon? Patrol = null, Place? Supply = null, string? Label = null);

public partial class Game
{
    static readonly float[] ChartScales = [.055f, .10f, .17f, .28f, .43f];
    bool chartOpen;
    V2 chartFocus;
    int chartZoom = 2;
    string? chartMessage;
    bool CanOpenChart => !title && !controls && Run.IsActive;
    float ChartScale => ChartScales[chartZoom];

    void ToggleChart()
    {
        if (chartOpen)
        {
            chartOpen = false;
            return;
        }
        if (!CanOpenChart) return;
        departingMenu?.Hide();
        chartOpen = true;
        chartFocus = Run.Position;
        chartMessage = null;
        maneuverRequested = false;
    }

    void PanChart(float dt)
    {
        V2 move = new((Down(Key.Right) || Down(Key.D) ? 1 : 0) - (Down(Key.Left) || Down(Key.A) ? 1 : 0),
            (Down(Key.Down) || Down(Key.S) ? 1 : 0) - (Down(Key.Up) || Down(Key.W) ? 1 : 0));
        foreach (int device in Input.GetConnectedJoypads())
        {
            var stick = new V2(Input.GetJoyAxis(device, JoyAxis.LeftX), Input.GetJoyAxis(device, JoyAxis.LeftY));
            if (stick.LengthSquared() <= .12f) continue;
            usingController = true;
            move = stick;
        }
        chartFocus += move / Math.Max(1, move.Length()) * (dt * 545 / ChartScale);
    }

    void ZoomChart(int direction) => chartZoom = Math.Clamp(chartZoom + direction, 0, ChartScales.Length - 1);

    void HandleChartClick(InputEventMouseButton click)
    {
        usingController = false;
        switch (click.ButtonIndex)
        {
            case MouseButton.WheelUp: ZoomChart(1); break;
            case MouseButton.WheelDown: ZoomChart(-1); break;
            case MouseButton.Right:
                ClearChartCourse();
                break;
            case MouseButton.Left when hud.ChartResume.HasPoint(click.Position):
                ToggleChart();
                break;
            case MouseButton.Left when hud.ChartArea.HasPoint(click.Position):
                SetChartCourse(click.Position);
                break;
        }
    }

    void HandleChartButton(JoyButton button)
    {
        switch (button)
        {
            case JoyButton.Y or JoyButton.B or JoyButton.Start: ToggleChart(); break;
            case JoyButton.LeftShoulder: ZoomChart(-1); break;
            case JoyButton.RightShoulder: ZoomChart(1); break;
            case JoyButton.A: SetChartCourse(hud.ChartArea.GetCenter()); break;
            case JoyButton.X: ClearChartCourse(); break;
        }
    }

    void ClearChartCourse()
    {
        course.Clear();
        chartMessage = null;
    }

    void SetChartCourse(Vector2 pointer)
    {
        var delta = (pointer - hud.ChartArea.GetCenter()) / ChartScale;
        var order = hud.CourseAt(pointer) ?? new(chartFocus + new V2(delta.X, delta.Y));
        chartMessage = PlotChartOrder(order) ? order.Label ?? "Course plotted" : "Choose water with room to maneuver";
    }

    bool PlotChartOrder(ChartOrder order)
    {
        if (order.Patrol is { } beacon) return course.Plot(Run, beacon);
        if (order.Supply is { } place) return course.Plot(Run, place);
        return course.Plot(Run, order.Point);
    }

    public partial class Hud
    {
        static readonly Color ChartPaper = new("e2d1ab"), UnchartedPaper = new("c6bea5"), ChartInk = new("29474a"), ChartCoast = new("96a889"),
            ChartWater = new("80928b"), ChartGold = new("a45e29"), ChartTeal = new("296f69");

        public Rect2 ChartToggle => new(GetViewportRect().Size.X - 152, 229, 104, 27);
        public Rect2 ChartArea => new(new Vector2(38, 105), GetViewportRect().Size - new Vector2(76, 206));
        public Rect2 ChartResume => new(GetViewportRect().Size - new Vector2(232, 74), new Vector2(194, 39));

        void DrawVoyageChart(Voyage run, Vector2 size)
        {
            var area = ChartArea;
            var screen = area.GetCenter();
            float scale = Game.ChartScale;
            Vector2 Plot(V2 point) => screen + NauticalPalette.G(point - Game.chartFocus) * scale;
            DrawRect(new(Vector2.Zero, size), NauticalPalette.Navy);
            DrawRect(area, UnchartedPaper);
            var tileSize = Vector2.One * (OceanWorld.ChartTileSize * scale);
            foreach (var tile in run.World.ChartedWater)
            {
                var corner = Plot(new V2(tile.X, tile.Y) * OceanWorld.ChartTileSize);
                var tileBounds = new Rect2(corner.Floor(), (corner + tileSize).Ceil() - corner.Floor());
                if (tileBounds.Intersects(area)) DrawRect(tileBounds, ChartPaper);
            }
            DrawChartGrid(area, screen, scale);
            foreach (var place in run.World.Discovered.Values)
            {
                if (run.World.Depletion.ContainsKey(place.Id)) continue;
                var at = Plot(place.Position);
                if (!area.Grow(place.Radius * scale + 14).HasPoint(at)) continue;
                DrawChartPlace(place, area, at, scale);
            }
            DrawChartRoute(run, Plot);
            if (!run.BossSpawned)
            {
                foreach (var beacon in run.Beacons)
                {
                    var at = Plot(beacon.Position);
                    if (!area.Grow(-13).HasPoint(at)) continue;
                    var color = beacon.Lit ? ChartTeal : ChartGold;
                    DrawCircle(at, 10, ChartPaper);
                    DrawColoredPolygon([at + new Vector2(0, -7), at + new Vector2(7, 0), at + new Vector2(0, 7), at + new Vector2(-7, 0)], color);
                    var order = new ChartOrder(beacon.Position,
                        !beacon.Lit && !run.Salvage.Towing && beacon.Objective == BeaconObjective.Patrol ? beacon : null,
                        Label: beacon.Name);
                    courses.Add((new(at - Vector2.One * 11, Vector2.One * 22), order));
                    Text(at + new Vector2(13, -4), beacon.Name, 15, true, ChartInk);
                }
                if (run.SalvageAvailable && !run.Salvage.Towing)
                {
                    var at = Plot(run.Salvage.Position);
                    if (area.Grow(-13).HasPoint(at))
                    {
                        DrawCircle(at, 10, ChartPaper);
                        DrawLine(at + new Vector2(-4, -8), at + new Vector2(-4, 8), ChartGold, 2, true);
                        DrawColoredPolygon([at + new Vector2(-3, -7), at + new Vector2(8, -3), at + new Vector2(-3, 2)], ChartGold);
                        courses.Add((new(at - Vector2.One * 12, Vector2.One * 24), new(run.Salvage.Position, Label: "Wreck salvage")));
                    }
                }
            }
            else if (run.Enemies.FirstOrDefault(enemy => enemy.Kind == EnemyKind.Leviathan && enemy.Health > 0) is { } boss)
            {
                var at = Plot(boss.Position);
                if (area.Grow(-10).HasPoint(at))
                {
                    DrawCircle(at, 7, ChartGold);
                    Text(at + new Vector2(11, 6), "Crownclaw", 15, true, ChartInk);
                }
            }

            var boat = Plot(run.Position);
            if (area.Grow(-15).HasPoint(boat))
            {
                DrawCircle(boat, 13, ChartPaper);
                Vector2[] arrow = [new(0, -11), new(-7, 8), new(0, 4), new(7, 8)];
                DrawColoredPolygon(arrow.Select(point => boat + point.Rotated(run.Heading)).ToArray(), ChartInk);
            }
            if (Game.usingController)
            {
                DrawArc(screen, 13, 0, Mathf.Tau, 24, ChartInk, 2, true);
                DrawCircle(screen, 2, ChartInk);
            }
            DrawChartFrame(area, size, scale);
        }

        void DrawChartGrid(Rect2 area, Vector2 screen, float scale)
        {
            float step = scale * (scale <= .10f ? 1200 : 600);
            var offset = NauticalPalette.G(Game.chartFocus) * scale;
            var x0 = area.Position.X + Mathf.PosMod(screen.X - offset.X - area.Position.X, step);
            var y0 = area.Position.Y + Mathf.PosMod(screen.Y - offset.Y - area.Position.Y, step);
            var ink = new Color(ChartWater, .37f);
            for (float x = x0; x < area.End.X; x += step)
                DrawLine(new(x, area.Position.Y), new(x, area.End.Y), ink, 1, true);
            for (float y = y0; y < area.End.Y; y += step)
                DrawLine(new(area.Position.X, y), new(area.End.X, y), ink, 1, true);
        }

        void DrawChartPlace(Place place, Rect2 area, Vector2 at, float scale)
        {
            if (place.Shape is { } shape)
            {
                var shore = shape.Shore.Select(point => at + NauticalPalette.G(point) * scale).ToArray();
                DrawColoredPolygon(shore, ChartCoast);
                DrawPolyline(shore.Append(shore[0]).ToArray(), ChartInk, 1, true);
                return;
            }
            if (!area.Grow(-12).HasPoint(at)) return;
            switch (place.Kind)
            {
                case PlaceKind.Harbor:
                    DrawCircle(at, Math.Max(8, place.Radius * scale), ChartCoast);
                    ChartAnchor(at, ChartInk);
                    Text(at + new Vector2(12, 5), "Harbor", 15, true, ChartInk);
                    break;
                case PlaceKind.Rock:
                    DrawCircle(at, Math.Max(2, place.Radius * scale), ChartInk);
                    break;
                case PlaceKind.Current:
                    var current = NauticalPalette.G(OceanWorld.FlowDirection(place));
                    DrawLine(at - current * 10, at + current * 10, ChartTeal, 2, true);
                    DrawLine(at + current * 10, at + current * 4 + current.Orthogonal() * 4, ChartTeal, 2, true);
                    DrawLine(at + current * 10, at + current * 4 - current.Orthogonal() * 4, ChartTeal, 2, true);
                    break;
                case PlaceKind.Whirlpool:
                    DrawArc(at, 7, .4f, 5, 19, ChartTeal, 2, true);
                    DrawArc(at, 3, 2, 4.4f, 10, ChartTeal, 1.5f, true);
                    break;
                case PlaceKind.Shipwreck:
                    DrawArc(at, 8, .22f, 4.8f, 22, ChartInk, 2, true);
                    DrawLine(at - Vector2.One * 4, at + Vector2.One * 4, ChartInk, 2, true);
                    break;
                case PlaceKind.Treasure:
                    DrawCircle(at, 10, ChartPaper);
                    DrawRect(new(at - new Vector2(7, 5), new Vector2(14, 10)), ChartGold);
                    DrawLine(at - new Vector2(6, 1), at + new Vector2(6, -1), ChartPaper, 1, true);
                    courses.Add((new(at - Vector2.One * 11, Vector2.One * 22), new(place.Position, Supply: place, Label: "Beach cache · XP")));
                    break;
                case PlaceKind.Barrel:
                    DrawCircle(at, 9, ChartPaper);
                    DrawLine(at - new Vector2(5, 0), at + new Vector2(5, 0), ChartTeal, 3, true);
                    DrawLine(at - new Vector2(0, 5), at + new Vector2(0, 5), ChartTeal, 3, true);
                    courses.Add((new(at - Vector2.One * 11, Vector2.One * 22), new(place.Position, Supply: place, Label: "Repair barrel · +25 hull")));
                    break;
            }
        }

        void DrawChartRoute(Voyage run, Func<V2, Vector2> plot)
        {
            var from = plot(run.Position);
            foreach (var point in Game.course.Ahead)
            {
                var to = plot(point);
                DrawDashedLine(from, to, ChartTeal, 2.3f, 8, true, true);
                from = to;
            }
            if (Game.course.Destination is { } destination)
                DrawCircle(plot(destination), 6, ChartTeal, false, 2, true);
        }

        void DrawChartFrame(Rect2 area, Vector2 size, float scale)
        {
            DrawRect(new(0, 0, size.X, area.Position.Y), NauticalPalette.Navy);
            DrawRect(new(0, area.End.Y, size.X, size.Y - area.End.Y), NauticalPalette.Navy);
            DrawRect(new(0, area.Position.Y, area.Position.X, area.Size.Y), NauticalPalette.Navy);
            DrawRect(new(area.End.X, area.Position.Y, size.X - area.End.X, area.Size.Y), NauticalPalette.Navy);
            DrawRect(area, NauticalPalette.Gold, false, 1.5f);
            Text(new(area.Position.X, 50), "Voyage chart", 36, true);
            string controls = Game.usingController ? "Left stick pan   ·   LB / RB zoom   ·   A plot   ·   X clear"
                : "Arrows pan   ·   Scroll zoom   ·   Click to plot   ·   Right-click to clear";
            Text(new(area.Position.X, 82), controls, 17);
            DrawRect(new(area.End.X - 162, 68, 13, 13), ChartPaper);
            Text(new(area.End.X - 139, 80), "Surveyed water", 15);
            var north = new Vector2(area.End.X - 33, area.Position.Y + 45);
            DrawArc(north, 16, 0, Mathf.Tau, 28, ChartWater, 1, true);
            DrawCircle(north, 15, ChartPaper);
            DrawColoredPolygon([north + new Vector2(0, -17), north + new Vector2(-5, 1), north,
                north + new Vector2(5, 1)], ChartInk);
            DrawColoredPolygon([north + new Vector2(0, 13), north + new Vector2(-4, 2), north,
                north + new Vector2(4, 2)], ChartWater);
            Text(north + new Vector2(-5, -21), "N", 15, true, ChartInk);
            int meters = scale < .17f ? 1000 : 400;
            var measure = area.End - new Vector2(24 + meters * scale, 20);
            DrawLine(measure, measure + new Vector2(meters * scale, 0), ChartInk, 2, true);
            Text(measure - new Vector2(0, 6), $"{meters} m", 13, color: ChartInk);

            var pointer = Game.usingController ? area.GetCenter() : Game.uiPointer;
            string? hover = CourseAt(pointer)?.Label;
            string status = hover ?? Game.chartMessage ?? "Choose a beacon, supplies, or a point in open water.";
            Text(new(area.Position.X, size.Y - 50), status, 18, true, NauticalPalette.Gold);
            var resume = ChartResume;
            var accent = resume.HasPoint(Game.uiPointer) ? NauticalPalette.Aqua : new Color("214654");
            DrawStyleBox(Game.Box(accent, 7), resume);
            Text(resume.Position + new Vector2(15, 26), Game.usingController ? "Y · Resume sailing" : "Tab · Resume sailing", 17,
                color: resume.HasPoint(Game.uiPointer) ? NauticalPalette.Navy : NauticalPalette.Cream);
        }
    }
}
