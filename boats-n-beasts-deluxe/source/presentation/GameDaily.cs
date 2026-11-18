using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    const int DailyBoardDays = 7;
    DailyChallenge? daily;
    DateOnly shownDailyDate;
    bool dailyPractice;
    int dailyBonus;

    void OpenDaily() => OpenDailyChart(DailyChallenge.Today.Day);

    void OpenDailyChart(DateOnly day, bool retainFocus = false)
    {
        var challenge = DailyChallenge.For(day);
        daily = challenge;
        choosingBoat = true;
        PreviewRun(challenge.Seed, challenge.Boat, Charter.Coastguard);
        if (retainFocus) RefocusDeparture(DailyButtonName(day));
        else BuildMenu();
    }

    void ReturnToDailyBoard(DateOnly day)
    {
        var today = DailyChallenge.Today.Day;
        ReturnToHarbor(true, DailyChallenge.For(BoardDate(day, today)));
    }

    static DateOnly BoardDate(DateOnly day, DateOnly today) =>
        day < today.AddDays(1 - DailyBoardDays) || day > today ? today : day;

    void RefreshDailyBoard()
    {
        if (!title || daily is not { } challenge) return;
        var today = DailyChallenge.Today.Day;
        if (today == shownDailyDate) return;
        var selected = challenge.Day == shownDailyDate ? today : BoardDate(challenge.Day, today);
        OpenDailyChart(selected);
    }

    static string DailyButtonName(DateOnly day) => $"Daily_{day.DayNumber}";

    double DailyTarget(DailyChallenge challenge, bool practice) =>
        practice ? log.PracticeTime(challenge.Day) : log.DailyTime(challenge.Day);

    void DailyMenu(DailyChallenge challenge)
    {
        var today = DailyChallenge.Today.Day;
        shownDailyDate = today;
        bool practice = challenge.Day != today;
        var col = Panel(796, "Daily charts", "A new chart at midnight UTC · Practice the previous six");
        var columns = new HBoxContainer();
        columns.AddThemeConstantOverride("separation", 17);
        col.AddChild(columns);

        var dates = new VBoxContainer { CustomMinimumSize = new(306, 0) };
        dates.AddThemeConstantOverride("separation", 6);
        columns.AddChild(dates);
        for (int i = 0; i < DailyBoardDays; i++)
        {
            var day = today.AddDays(-i);
            var entry = DailyChallenge.For(day);
            string label = i == 0 ? "Today" : $"{day:MMM d}";
            double time = DailyTarget(entry, i != 0);
            var button = Button($"{label} · {entry.Name}{(time > 0 ? "  ✓" : "")}",
                () => OpenDailyChart(day, true), primary: day == challenge.Day);
            button.Name = DailyButtonName(day);
            button.Alignment = HorizontalAlignment.Left;
            button.AccessibilityName = $"{label} · {entry.Name}{(time > 0 ? " · Completed" : "")}";
            dates.AddChild(button);
        }

        var sheet = new PanelContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        sheet.AddThemeStyleboxOverride("panel", Box(new Color("0e2833"), 8, new Color("365462")));
        columns.AddChild(sheet);
        var details = new VBoxContainer();
        details.AddThemeConstantOverride("separation", 12);
        sheet.AddChild(details);
        details.AddChild(Label(practice ? $"{challenge.Day:MMM d} UTC · Practice" : $"{challenge.Day:MMM d} UTC · Today",
            16, color: NauticalPalette.Gold));
        details.AddChild(Label(challenge.Name, 28, true));
        details.AddChild(Label(challenge.Rule, 20));
        details.AddChild(Label($"{Run.Spec.Name}  ·  {Run.Spec.Maneuver}", 18, true));
        details.AddChild(Label(Run.Spec.Description, 17));
        double best = DailyTarget(challenge, practice);
        if (best > 0) details.AddChild(Label($"Best on this chart · {HuntTimeText(best)}", 17, color: NauticalPalette.Aqua));
        if (practice) details.AddChild(Label("Practice clears have their own times. Today’s chart counts toward the streak.", 15));
        else if (best <= 0) details.AddChild(Label($"First clear earns {DailyChallenge.Reward} silver.", 17, color: NauticalPalette.Aqua));
        AddDepartureButtons(col, practice ? Button("Practice this chart", Start, true) : null);
    }

    string? DailyResult()
    {
        if (daily is not { } challenge) return null;
        string mode = dailyPractice ? "Practice" : "Daily";
        if (!challenge.Qualifies(Run))
        {
            string status = Run.BossSlain ? $"{mode} goal missed" : challenge.Name;
            return $"{status} · {challenge.Progress(Run)}";
        }
        return dailyBonus > 0 ? $"Daily clear · +{dailyBonus} silver bonus" : $"{mode} clear · {challenge.Name}";
    }

    static string HuntTimeText(double seconds)
    {
        int tenths = Math.Max(0, (int)(seconds * 10));
        return $"{tenths / 600}:{tenths / 10 % 60:00}.{tenths % 10}";
    }
}
