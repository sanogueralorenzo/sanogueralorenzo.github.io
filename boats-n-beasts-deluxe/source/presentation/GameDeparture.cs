using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    Charter? previewCharter;

    void BoatMenu()
    {
        var charter = previewCharter ?? selectedCharter;
        var rules = CharterRules.For(charter);
        bool owned = log.Owns(charter);
        double best = log.BestTime(selectedBoat, charter);
        string summary = $"{log.Silver} silver in the hold";
        if (owned && best > 0) summary += $"  ·  Personal best {HuntTimeText(best)}";
        var col = Panel(684, "Chart a voyage", summary);

        var boats = new HBoxContainer();
        boats.AddThemeConstantOverride("separation", 8);
        col.AddChild(boats);
        foreach (var boat in Enum.GetValues<BoatKind>())
        {
            var choice = Button(BoatSpec.For(boat).Name, () =>
            {
                selectedBoat = boat;
                PreviewRun(selectedSeed, selectedBoat, selectedCharter);
                RefocusDeparture(boat.ToString());
            }, selectedBoat == boat);
            choice.Name = boat.ToString();
            choice.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
            boats.AddChild(choice);
        }

        var spec = BoatSpec.For(selectedBoat);
        col.AddChild(Label($"{spec.Maneuver} · {spec.ManeuverSeconds}s recharge", 23, true));
        col.AddChild(Label($"{spec.Hull * rules.HullFactor:0} hull  ·  {spec.Speed:0} sailing speed", 16, color: NauticalPalette.Gold));
        var maneuver = Label(spec.Description, 18);
        maneuver.CustomMinimumSize = new(0, 48);
        col.AddChild(maneuver);
        col.AddChild(Label("Voyage charter", 22, true));

        var charters = new HBoxContainer();
        charters.AddThemeConstantOverride("separation", 8);
        col.AddChild(charters);
        foreach (var option in Enum.GetValues<Charter>())
            charters.AddChild(CharterChoice(option, charter == option));

        var terms = Label(rules.Description, 17);
        terms.CustomMinimumSize = new(0, 46);
        col.AddChild(terms);

        Button? sign = null;
        if (!owned)
        {
            int missing = rules.Price - log.Silver;
            sign = Button(missing > 0 ? $"Need {missing} more silver" : $"Unlock {rules.Name} · {rules.Price} silver", () =>
            {
                if (!log.Unlock(charter)) return;
                SelectCharter(charter);
                audio.Play("upgrade");
                BuildMenu();
            }, primary: true, disabled: missing > 0);
            sign.AddThemeColorOverride("font_disabled_color", NauticalPalette.Gold);
        }

        AddDepartureButtons(col, sign);
    }

    Button CharterChoice(Charter charter, bool selected)
    {
        var rules = CharterRules.For(charter);
        bool owned = log.Owns(charter);
        bool affordable = log.Silver >= rules.Price;
        string state = owned ? "Unlocked" : affordable ? $"{rules.Price} silver · Ready" : $"{log.Silver} / {rules.Price} silver";
        var accent = owned ? NauticalPalette.Aqua : NauticalPalette.Gold;
        var button = Button("", () =>
        {
            if (owned) SelectCharter(charter);
            else previewCharter = charter;
            RefocusDeparture(charter.ToString());
        });
        button.Name = charter.ToString();
        button.AccessibilityName = rules.Name;
        button.AccessibilityDescription = selected ? $"{state}. Selected." : state;
        button.TooltipText = $"{rules.Name} · {state}";
        button.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        button.CustomMinimumSize = new(0, 74);
        button.AddThemeStyleboxOverride("normal",
            Box(selected ? new Color("1b4650") : new Color("102b39"), 8, selected ? accent : new Color("365462")));
        button.AddThemeStyleboxOverride("hover", Box(new Color("214553"), 8, accent));
        button.AddThemeStyleboxOverride("pressed", Box(new Color("265763"), 8, accent));

        var caption = new VBoxContainer();
        caption.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        caption.OffsetLeft = 12;
        caption.OffsetRight = -12;
        caption.OffsetTop = 11;
        caption.AddThemeConstantOverride("separation", 3);
        caption.AddChild(Label(rules.Name, 19, true));
        caption.AddChild(Label(state, 15, color: accent));
        button.AddChild(caption);
        ReleaseMenuInput(caption);
        return button;
    }

    void SelectCharter(Charter charter)
    {
        previewCharter = null;
        if (selectedCharter == charter) return;
        selectedCharter = charter;
        PreviewRun(selectedSeed, selectedBoat, selectedCharter);
    }

    void RefocusDeparture(string name)
    {
        BuildMenu();
        if (menuRoot.FindChild(name, true, false) is Button choice) choice.GrabFocus();
    }

    void AddDepartureButtons(VBoxContainer col, Button? primary = null)
    {
        var actions = new HBoxContainer();
        actions.AddThemeConstantOverride("separation", 8);
        col.AddChild(actions);
        actions.AddChild(Button("Back", () =>
        {
            CloseDeparture();
            BuildMenu();
        }));
        var action = primary ?? Button("Set sail", Start, true);
        action.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        actions.AddChild(action);
        if (!action.Disabled) action.GrabFocus();
    }

    void CloseDeparture()
    {
        choosingBoat = false;
        previewCharter = null;
        if (!daily.HasValue && !replayingHunt.HasValue) return;
        daily = null;
        dailyPractice = false;
        replayingHunt = null;
        PreviewRun(selectedSeed, selectedBoat, selectedCharter);
    }

    string? CharterProgress()
    {
        foreach (var charter in Enum.GetValues<Charter>())
        {
            if (log.Owns(charter)) continue;
            var rules = CharterRules.For(charter);
            return log.Silver >= rules.Price ? $"{rules.Name} charter ready to unlock"
                : $"{log.Silver} / {rules.Price} silver for the {rules.Name} charter";
        }
        return null;
    }
}
