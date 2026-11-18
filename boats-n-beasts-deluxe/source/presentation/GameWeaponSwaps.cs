using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    int? pendingSwap;

    void SwapWeaponMenu(int incoming)
    {
        var column = Panel(660, $"Fit {Voyage.UpgradeNames[incoming]}",
            $"Choose a weapon to replace. Your starting {Voyage.UpgradeNames[(int)BoatRig.Starter(Run.Boat)]} stays fitted.");
        var previous = Run.ActiveCombo;
        var pair = WeaponCombo.ForUpgrade(incoming);
        int partner = pair?.Partner(incoming) ?? -1;
        for (int index = 0; index < Run.Weapons.Length; index++)
        {
            int outgoing = index;
            if (!Run.CanSwapWeapon(incoming, outgoing)) continue;
            int rank = Run.Rank(outgoing);
            bool losesPair = previous != null && (outgoing == (int)previous.First || outgoing == (int)previous.Second);
            bool makesPair = partner >= 0 && partner != outgoing && Run.Rank(partner) > 0;
            string? note = makesPair && losesPair ? $"{previous!.Name} → {pair!.Name}"
                : makesPair ? $"{pair!.Name} · {pair.Description}"
                : losesPair ? $"{previous!.Name} will break" : null;
            AddRefitRow(column, outgoing, $"Replace {Voyage.UpgradeNames[outgoing]} · Keep rank {rank}",
                Run.WeaponReadout((WeaponKind)incoming, rank), () =>
                {
                    if (!Run.SwapWeapon(incoming, outgoing)) return;
                    pendingSwap = null;
                    BuildMenu();
                }, note, makesPair ? NauticalPalette.Gold : NauticalPalette.Coral);
        }
        column.AddChild(Button("Back to refit", () => { pendingSwap = null; BuildMenu(); }));
    }
}
