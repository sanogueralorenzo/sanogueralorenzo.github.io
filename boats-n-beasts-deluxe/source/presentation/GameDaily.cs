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

    void DailyMenu(DailyChallenge challenge)
    {
        var col = Panel(620, challenge.Name, $"{challenge.Day:MMM d} UTC  ·  {Run.Spec.Name}");
        col.AddChild(Label(challenge.Rule, 22, true));
        col.AddChild(Label($"{Run.Spec.Maneuver} · {Run.Spec.ManeuverSeconds}s recharge", 17, color: NauticalPalette.Gold));
        col.AddChild(Label(Run.Spec.Description, 17));
        double best = log.DailyTime(challenge.Day);
        string reward = best > 0 ? $"Personal best {HuntTimeText(best)}" : $"First clear earns {DailyChallenge.Reward} silver.";
        col.AddChild(Label(reward, 17, color: NauticalPalette.Aqua));
        AddDepartureButtons(col);
    }

    string? DailyResult()
    {
        if (daily is not { } challenge) return null;
        if (!challenge.Qualifies(Run))
            return $"{(Run.BossSlain ? "Daily goal missed" : challenge.Name)} · {challenge.Progress(Run)}";
        return dailyBonus > 0 ? $"Daily clear · +{dailyBonus} silver bonus" : $"Daily clear · {challenge.Name}";
    }

    static string HuntTimeText(double seconds)
    {
        int tenths = Math.Max(0, (int)(seconds * 10));
        return $"{tenths / 600}:{tenths / 10 % 60:00}.{tenths % 10}";
    }
}
