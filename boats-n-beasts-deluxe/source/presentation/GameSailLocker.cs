using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    bool sailLocker;
    int earnedSails;
    SailLivery previewSail;

    void OpenSailLocker()
    {
        sailLocker = true;
        previewSail = log.Livery;
        BuildMenu();
    }

    void CloseSailLocker()
    {
        sailLocker = false;
        ocean.Livery = log.Livery;
    }

    void SailLockerMenu()
    {
        var design = SailDesign.For(previewSail);
        var col = Panel(505, "Sail locker", "Preview a sail on the boat at the dock.", besideBoat: true);
        Button? selected = null;
        foreach (var option in SailDesign.All)
        {
            string state = option.Livery == log.Livery ? "Equipped" : log.Owns(option) ? "Unlocked" : "Locked";
            var button = Button($"{option.Name}  ·  {state}", () =>
            {
                previewSail = ocean.Livery = option.Livery;
                BuildMenu();
            }, primary: option == design);
            col.AddChild(button);
            if (option == design) selected = button;
        }

        col.AddChild(Label(design.Requirement, 17, color: NauticalPalette.Gold));
        var actions = new HBoxContainer();
        actions.AddThemeConstantOverride("separation", 8);
        col.AddChild(actions);
        actions.AddChild(Button("Back to log", () => { CloseSailLocker(); BuildMenu(); }));
        var equip = Button("Equip sail", () =>
        {
            if (!log.Equip(design)) return;
            audio.Play("upgrade");
            BuildMenu();
        }, true, disabled: !log.Owns(design) || design.Livery == log.Livery);
        equip.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        actions.AddChild(equip);
        selected?.GrabFocus();
    }

    string SailUnlockResult() => earnedSails == 0 ? "" : "\nSails unlocked · " + string.Join(", ",
        SailDesign.All.Where(design => (earnedSails & design.Flag) != 0).Select(design => design.Name));
}
