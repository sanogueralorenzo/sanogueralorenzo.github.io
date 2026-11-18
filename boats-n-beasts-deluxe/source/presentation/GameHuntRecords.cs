using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Game
{
    HuntRecord? replayingHunt;

    void JournalMenu()
    {
        string wins = log.Wins == 1 ? "1 win" : $"{log.Wins} wins";
        string voyages = log.Voyages == 1 ? "1 voyage" : $"{log.Voyages} voyages";
        string haul = log.BestKills == 1 ? "1 beast" : $"{log.BestKills} beasts";
        var col = Panel(682, "Captain’s log",
            $"{log.Silver} silver  ·  {wins} in {voyages}\nBest haul {haul}  ·  Longest chain {log.BestChain}\nDaily clears {log.DailyClears}  ·  Streak {log.DailyStreak(DailyChallenge.Today.Day)}");
        col.AddChild(Label("Fastest regular hunts", 22, true));
        var times = new GridContainer { Columns = 4 };
        times.AddThemeConstantOverride("h_separation", 12);
        times.AddThemeConstantOverride("v_separation", 7);
        col.AddChild(times);
        times.AddChild(new Control { CustomMinimumSize = new(112, 0) });
        foreach (var charter in Enum.GetValues<Charter>())
        {
            var label = Label(CharterRules.For(charter).Name, 16, color: NauticalPalette.Gold);
            label.AutowrapMode = TextServer.AutowrapMode.Off;
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
            times.AddChild(label);
        }

        bool hasReplay = false;
        foreach (var boat in Enum.GetValues<BoatKind>())
        {
            var name = Label(BoatSpec.For(boat).Name, 18, true);
            name.AutowrapMode = TextServer.AutowrapMode.Off;
            name.VerticalAlignment = VerticalAlignment.Center;
            times.AddChild(name);
            foreach (var charter in Enum.GetValues<Charter>())
            {
                var hunt = log.BestHunt(boat, charter);
                if (hunt.Seed != 0 && log.Owns(charter))
                {
                    hasReplay = true;
                    var replay = Button($"{HuntTimeText(hunt.Time)}  ↻", () => OpenHuntReplay(boat, charter, hunt));
                    replay.AccessibilityName = $"Replay {BoatSpec.For(boat).Name} · {CharterRules.For(charter).Name} · {HuntTimeText(hunt.Time)}";
                    replay.TooltipText = "Replay this chart";
                    times.AddChild(replay);
                }
                else
                {
                    var time = Label(hunt.Time > 0 ? HuntTimeText(hunt.Time) : "—", 16,
                        color: hunt.Time > 0 ? NauticalPalette.Aqua : new Color(NauticalPalette.Cream, .52f));
                    time.HorizontalAlignment = HorizontalAlignment.Center;
                    time.VerticalAlignment = VerticalAlignment.Center;
                    time.CustomMinimumSize = new(0, 34);
                    times.AddChild(time);
                }
            }
        }
        if (hasReplay) col.AddChild(Label("Select a time with ↻ to replay its chart.", 16, color: NauticalPalette.Aqua));

        var actions = new HBoxContainer();
        actions.AddThemeConstantOverride("separation", 8);
        col.AddChild(actions);
        var locker = Button("Sail locker", OpenSailLocker);
        locker.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        actions.AddChild(locker);
        AddMuteButton(actions);
        col.AddChild(Button("Back", () => { journal = false; BuildMenu(); }, true));
    }

    void OpenHuntReplay(BoatKind boat, Charter charter, HuntRecord hunt)
    {
        replayingHunt = hunt;
        choosingBoat = true;
        PreviewRun(hunt.Seed, boat, charter);
        BuildMenu();
    }

    void HuntReplayMenu(HuntRecord hunt)
    {
        var col = Panel(596, "Replay a record chart", $"{Run.Spec.Name}  ·  {Run.Rules.Name}");
        col.AddChild(Label($"Time to beat · {HuntTimeText(hunt.Time)}", 23, true, NauticalPalette.Gold));
        AddDepartureButtons(col);
    }

    double RecordTarget(Voyage run)
    {
        if (daily.HasValue || run.BossSlain) return 0;
        var hunt = log.BestHunt(run.Boat, run.Charter);
        return hunt.Seed == run.World.Seed ? hunt.Time : 0;
    }
}
