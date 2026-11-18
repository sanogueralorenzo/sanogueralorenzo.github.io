using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    DailyChallenge? daily;
    int dailyBonus;

    void OpenDaily()
    {
        var challenge = DailyChallenge.Today;
        daily = challenge;
        choosingBoat = true;
        PreviewRun(challenge.Seed, challenge.Boat, Charter.Coastguard);
        BuildMenu();
    }

    void RestoreOpenChart()
    {
        if (!daily.HasValue) return;
        daily = null;
        PreviewRun(selectedSeed, selectedBoat, selectedCharter);
    }

    void DailyMenu(DailyChallenge challenge)
    {
        var col = Panel(620, challenge.Name, $"{challenge.Day:MMM d} UTC  ·  {Run.Spec.Name}");
        col.AddChild(Label(challenge.Rule, 22, true));
        col.AddChild(Label($"{Run.Spec.Maneuver} · {Run.Spec.ManeuverSeconds}s recharge", 17, color: NauticalPalette.Gold));
        col.AddChild(Label(Run.Spec.Description, 17));
        double best = log.DailyTime(challenge.Day);
        string reward = best > 0 ? $"Personal best {DailyTimeText(best)}" : $"First clear earns {DailyChallenge.Reward} silver.";
        col.AddChild(Label(reward, 17, color: NauticalPalette.Aqua));
        AddDepartureButtons(col);
    }

    string DailyResult()
    {
        if (daily is not { } challenge) return "";
        if (!challenge.Qualifies(Run))
            return $"\n{(Run.BossSlain ? "Daily goal missed" : "Daily")} · {challenge.Progress(Run)}";
        string best = $"Daily clear · Personal best {DailyTimeText(log.DailyTime(challenge.Day))}";
        if (dailyBonus > 0) best += $" · +{dailyBonus} silver";
        return $"\n{best}";
    }

    static string DailyTimeText(double seconds)
    {
        int tenths = Math.Max(0, (int)(seconds * 10));
        return $"{tenths / 600}:{tenths / 10 % 60:00}.{tenths % 10}";
    }
}
