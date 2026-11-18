using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game
{
    bool CanUseHarborControls => !title && !controls && Run.IsActive && Run.AtRepairBerth;

    void UseHarborRepair()
    {
        if (Run.ToggleHarborRepairs()) course.Clear();
    }

    public partial class Hud
    {
        public Rect2 RepairControl { get; private set; }

        void DrawHarborGuide(Voyage run, Vector2 size, int statusInset)
        {
            if (!run.IsActive || !run.RepairsAvailable || run.Health >= run.MaxHealth) return;
            if (!run.AtRepairBerth)
            {
                bool critical = run.Health <= run.MaxHealth * .45f && !run.Salvage.Towing;
                if (critical || V2.DistanceSquared(run.Position, StartingArea.RepairBerth) <= 700 * 700)
                    DrawCourseMarker(StartingArea.RepairBerth, "Repair berth", "Tie up to repair", NauticalPalette.Aqua,
                        size, allowOffscreen: critical);
                return;
            }

            var at = new Vector2(24, 280 + statusInset);
            var box = new Rect2(at, new Vector2(254, 86));
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .94f), 8, new Color(NauticalPalette.Aqua, .50f)), box);
            Text(at + new Vector2(13, 26), "Repair berth", 20, true, NauticalPalette.Aqua);
            string key = Game.usingController ? "A" : "F";
            var action = new Rect2(at + new Vector2(12, 38), new Vector2(230, 32));
            if (run.Repairing)
            {
                RepairControl = action;
                Text(at + new Vector2(13, 53), $"Repairs underway  ·  {key} to cast off", 14);
                Bar(at + new Vector2(13, 65), new(228, 6), run.RepairProgress, NauticalPalette.Aqua);
                return;
            }
            if (run.CanTieUp)
            {
                RepairControl = action;
                Color fill = action.HasPoint(Game.uiPointer) ? NauticalPalette.Aqua : new Color("28515e");
                DrawStyleBox(Game.Box(fill, 6), action);
                float restore = Math.Min(Voyage.HarborRepairHull, run.MaxHealth - run.Health);
                Text(action.Position + new Vector2(10, 22), $"{key} · Tie up for +{restore:0} hull", 15,
                    color: action.HasPoint(Game.uiPointer) ? NauticalPalette.Navy : NauticalPalette.Cream);
            }
            else Text(action.Position + new Vector2(1, 21), "Slow down to tie up", 15);
        }

        void DrawRepairChartMark(Vector2 at, Color paper, Color ink)
        {
            var icon = new Rect2(at - Vector2.One * 8, Vector2.One * 16);
            DrawCircle(at, 8, paper);
            DrawArc(at, 7, 0, Mathf.Tau, 24, ink, 1.3f, true);
            DrawLine(at - new Vector2(4, 0), at + new Vector2(4, 0), ink, 1.8f, true);
            DrawLine(at - new Vector2(0, 4), at + new Vector2(0, 4), ink, 1.8f, true);
            courses.Add((icon, new(StartingArea.RepairBerth, Label: "Repair berth")));
        }
    }
}
