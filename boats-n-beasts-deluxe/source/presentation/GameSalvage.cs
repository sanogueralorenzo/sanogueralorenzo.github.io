using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    public partial class Hud
    {
        void DrawSalvageGuide(Voyage run, Beacon delivery, Vector2 size, int statusInset)
        {
            bool premiumRoute = delivery == run.PremiumSalvageBeacon;
            var offer = premiumRoute ? null : run.PremiumSalvageBeacon;
            int width = offer != null ? 280 : 168;
            var at = new Vector2(24, 215 + statusInset);
            var color = run.TowTension > .72f ? NauticalPalette.Coral : NauticalPalette.Aqua;
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .94f), 7),
                new(at, new Vector2(width, offer != null ? 86 : 44)));
            Text(at + new Vector2(12, 21), run.TowTension > .72f ? "Towline strained" : "Towline", 15, true, color);
            Bar(at + new Vector2(12, 31), new(width - 24, 4), run.TowTension, color);
            if (offer != null)
            {
                var bounds = new Rect2(at + new Vector2(10, 43), new Vector2(width - 20, 33));
                bool hover = bounds.HasPoint(Game.uiPointer);
                DrawStyleBox(Game.Box(hover ? NauticalPalette.Gold : new Color("544431"), 6), bounds);
                Text(bounds.Position + new Vector2(9, 22), $"{offer.Name} · +{Voyage.PremiumSalvageBonus} silver", 15,
                    color: hover ? NauticalPalette.Navy : NauticalPalette.Gold);
                courses.Add((bounds, new(offer.Position, offer)));
            }

            DrawCourseMarker(delivery.Position, delivery.Name,
                premiumRoute ? $"Premium · +{Voyage.PremiumSalvageBonus} silver" : "Deliver salvage",
                premiumRoute ? NauticalPalette.Gold : NauticalPalette.Aqua, size, beacon: delivery);
        }
    }
}
