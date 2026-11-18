using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    double previousBest;

    void VoyageReport()
    {
        Record();
        bool won = Run.BossSlain;
        var column = Panel(718, won ? "Crownclaw defeated" : "Lost to the deep",
            $"{Run.Spec.Name}  ·  {Run.Rules.Name}  ·  Level {Run.Level}");
        if (!won) column.AddChild(Label(HullLossText(Run.LastHullHit), 18, color: NauticalPalette.Coral));
        else if (HuntRecordText() is { } record) column.AddChild(Label(record, 18, color: NauticalPalette.Aqua));

        var stats = new HBoxContainer();
        stats.AddThemeConstantOverride("separation", 8);
        column.AddChild(stats);
        AddReportStat(stats, HuntTimeText(Run.CombatTime), "Voyage time");
        AddReportStat(stats, $"{Run.BeaconsLit}/{Run.Beacons.Count}", "Beacons lit");
        AddReportStat(stats, $"{Run.Kills}", "Beasts defeated");
        AddReportStat(stats, $"+{Run.SilverEarned + dailyBonus}", "Silver earned");

        var detail = new List<string>();
        if (Run.LongestChain > 0) detail.Add($"Best chain {Run.LongestChain}");
        if (Run.CloseCalls > 0) detail.Add($"Close calls {Run.CloseCalls}");
        if (Run.Salvage.Delivered) detail.Add("Wreck salvage delivered");
        if (Run.FloatingCacheClaimed) detail.Add("Drifting cache secured");
        if (Run.HuntSignalBeacon != null) detail.Add("Hunt signal fired");
        if (Run.Charter == Charter.Stormchaser)
            detail.Add(log.Owns(SailDesign.For(SailLivery.Thunderhead)) ? $"Storm kills {Run.StormKills}"
                : $"Storm kills {Run.StormKills}/{SailDesign.ThunderheadKills} for Thunderhead");
        if (detail.Count > 0) column.AddChild(Label(string.Join("  ·  ", detail), 16));
        if (DailyResult() is { } dailyResult) column.AddChild(Label(dailyResult, 16, color: NauticalPalette.Aqua));
        if (SailUnlockResult() is { } sail) column.AddChild(Label(sail, 16, color: NauticalPalette.Gold));
        if (CharterProgress() is { } progress) column.AddChild(Label(progress, 16, color: NauticalPalette.Gold));

        DrawReportLoadout(column);
        var actions = new HBoxContainer();
        actions.AddThemeConstantOverride("separation", 8);
        column.AddChild(actions);
        bool canExplore = won && !daily.HasValue;
        if (canExplore) AddAction("Keep exploring", () => { Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true);
        AddAction(daily.HasValue ? "Retry daily" : "Retry this chart", Start, !canExplore);
        if (daily.HasValue) AddAction("Return to harbor", BackToTitle);
        else AddAction("Chart a new voyage", () => ReturnToHarbor(true));

        void AddAction(string text, Action run, bool primary = false)
        {
            var button = Button(text, run, primary);
            button.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
            actions.AddChild(button);
        }
    }

    void AddReportStat(HBoxContainer row, string value, string description)
    {
        var box = new PanelContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        box.AddThemeStyleboxOverride("panel", Box(new Color("0e2833"), 7));
        row.AddChild(box);
        var content = new VBoxContainer();
        content.AddThemeConstantOverride("separation", 2);
        box.AddChild(content);
        content.AddChild(Label(value, 26, true, NauticalPalette.Gold));
        content.AddChild(Label(description, 14));
    }

    void DrawReportLoadout(VBoxContainer column)
    {
        var finish = new List<string> { "Final loadout" };
        if (Run.ActiveCombo is { } combo) finish.Add(combo.Name);
        if (Run.Specialty != Specialty.None)
            finish.Add(Voyage.UpgradeNames[Voyage.FirstSpecialtyOption + (int)Run.Specialty - 1]);
        column.AddChild(Label(string.Join("  ·  ", finish), 20, true));
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 8);
        column.AddChild(row);
        for (int weapon = 0; weapon < Run.Weapons.Length; weapon++)
        {
            int rank = Run.Weapons[weapon];
            if (rank == 0) continue;
            var box = new PanelContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
            box.AddThemeStyleboxOverride("panel", Box(new Color("0d2933"), 7));
            row.AddChild(box);
            var item = new HBoxContainer();
            item.AddThemeConstantOverride("separation", 8);
            box.AddChild(item);
            item.AddChild(new UpgradeSymbol { Kind = weapon, CustomMinimumSize = new(40, 40) });
            var caption = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
            caption.AddThemeConstantOverride("separation", 1);
            caption.AddChild(Label(Voyage.UpgradeNames[weapon], 17, true));
            caption.AddChild(Label($"Rank {rank}", 14));
            item.AddChild(caption);
        }
    }

    string? HuntRecordText()
    {
        if (daily is { } challenge && !challenge.Qualifies(Run)) return null;
        if (previousBest <= 0) return daily.HasValue ? "First daily clear" : "First win with this boat and charter";
        double difference = Run.CombatTime - previousBest;
        if (Math.Abs(difference) < .05) return $"Matched personal best of {HuntTimeText(previousBest)}";
        return difference < 0 ? $"New personal best · {Math.Abs(difference):0.0}s faster"
            : $"Personal best {HuntTimeText(previousBest)} · {difference:0.0}s behind";
    }

    static string HullLossText(HullHit source) => source switch
    {
        HullHit.PufferBlast => "Final hit from a puffer blast",
        HullHit.CrownclawBomb => "Final hit from a Crownclaw bomb",
        HullHit.CrownclawCharge => "Final hit from Crownclaw’s charge",
        HullHit.Lightning => "Final hit from lightning",
        HullHit.Crownclaw => "Final hit from Crownclaw",
        HullHit.Keeper => "Final hit from Smuggler’s Light’s keeper",
        HullHit.Ray => "Final hit from a ray",
        HullHit.Serpent => "Final hit from a sea serpent",
        HullHit.Crab => "Final hit from a crab",
        _ => "Hull lost"
    };
}
