using BoatsNBeasts.Core;
using System.Globalization;
using Godot;
namespace BoatsNBeasts;

readonly record struct HuntRecord(double Time, uint Seed);

sealed class CaptainLog
{
    const string Path = "user://captain.cfg";
    const string PendingPath = "user://captain.pending";
    const string Section = "log";
    const string DailySection = "daily";
    const string SailSection = "sails";
    const string ChartSection = "charts";
    const string SeedSection = "record_seeds";
    public int Silver { get; private set; }
    public int Voyages { get; private set; }
    public int Wins { get; private set; }
    public int BestChain { get; private set; }
    public int BestKills { get; private set; }
    public bool Muted { get; private set; }
    public bool HasLitBeacon { get; private set; }
    public SailLivery Livery { get; private set; }
    int charters = 1;
    int sails = 1;
    readonly Dictionary<(BoatKind Boat, Charter Charter), HuntRecord> hunts = new();

    readonly Dictionary<int, double> dailyTimes = new();

    public HuntRecord BestHunt(BoatKind boat, Charter charter) => hunts.GetValueOrDefault((boat, charter));
    public double BestTime(BoatKind boat, Charter charter) => BestHunt(boat, charter).Time;
    public double DailyTime(DateOnly day) => dailyTimes.GetValueOrDefault(day.DayNumber);
    public int DailyClears => dailyTimes.Count;

    public int DailyStreak(DateOnly day)
    {
        int latest = day.DayNumber;
        if (!dailyTimes.ContainsKey(latest)) latest--;
        int count = 0;
        while (dailyTimes.ContainsKey(latest - count)) count++;
        return count;
    }

    public bool Owns(Charter charter) => (charters & (1 << (int)charter)) != 0;

    public bool Unlock(Charter charter)
    {
        int price = CharterRules.For(charter).Price;
        if (Owns(charter) || Silver < price) return false;
        charters |= 1 << (int)charter;
        Silver -= price;
        Save();
        return true;
    }

    public void Earn(int amount, bool litBeacon)
    {
        Silver += amount;
        HasLitBeacon |= litBeacon;
        Save();
    }

    public bool Owns(SailDesign design) => (sails & design.Flag) != 0;

    public bool Equip(SailDesign design)
    {
        if (!Owns(design) || Livery == design.Livery) return false;
        Livery = design.Livery;
        Save();
        return true;
    }

    public int EarnSails(Voyage run)
    {
        int added = UnlockSails(run, null);
        if (added != 0) Save();
        return added;
    }

    int UnlockSails(Voyage run, DailyChallenge? daily)
    {
        int before = sails;
        foreach (var design in SailDesign.All)
            if (!Owns(design) && design.Earned(run, daily)) sails |= design.Flag;
        return sails & ~before;
    }

    public (int DailyBonus, int NewSails) Record(Voyage run, DailyChallenge? daily)
    {
        Voyages++;
        BestKills = Math.Max(BestKills, run.Kills);
        BestChain = Math.Max(BestChain, run.LongestChain);
        if (run.BossSlain)
        {
            Wins++;
            if (!daily.HasValue)
            {
                var record = BestHunt(run.Boat, run.Charter);
                if (record.Time <= 0 || run.CombatTime < record.Time)
                    hunts[(run.Boat, run.Charter)] = new(run.CombatTime, run.World.Seed);
            }
        }
        int bonus = 0;
        if (daily is { } challenge && challenge.Qualifies(run))
        {
            int day = challenge.Day.DayNumber;
            if (dailyTimes.TryAdd(day, run.CombatTime))
            {
                bonus = DailyChallenge.Reward;
                Silver += bonus;
            }
            else dailyTimes[day] = Faster(dailyTimes[day], run.CombatTime);
        }
        int newSails = UnlockSails(run, daily);
        Save();
        return (bonus, newSails);
    }

    public void ToggleMute()
    {
        Muted = !Muted;
        Save();
    }

    public void Load()
    {
        var config = new ConfigFile();
        if (config.Load(Path) != Error.Ok) return;
        Silver = (int)config.GetValue(Section, "silver", 0);
        Voyages = (int)config.GetValue(Section, "voyages", 0);
        Wins = (int)config.GetValue(Section, "wins", 0);
        BestChain = (int)config.GetValue(Section, "chain", 0);
        BestKills = (int)config.GetValue(Section, "kills", 0);
        charters = (int)config.GetValue(Section, "charters", 1);
        Muted = (bool)config.GetValue(Section, "muted", false);
        HasLitBeacon = (bool)config.GetValue(Section, "lit_beacon", false);
        sails = (int)config.GetValue(SailSection, "owned", 1) | 1;
        int equipped = (int)config.GetValue(SailSection, "equipped", 0);
        if (equipped >= 0 && equipped < SailDesign.All.Length && Owns(SailDesign.All[equipped]))
            Livery = (SailLivery)equipped;
        foreach (var boat in Enum.GetValues<BoatKind>())
        foreach (var charter in Enum.GetValues<Charter>())
        {
            string key = ChartKey(boat, charter);
            double time = (double)config.GetValue(ChartSection, key, 0);
            long seed = (long)config.GetValue(SeedSection, key, 0);
            if (time > 0) hunts[(boat, charter)] = new(time, (uint)Math.Clamp(seed, 0, uint.MaxValue));
        }
        if (!config.HasSection(DailySection)) return;
        foreach (string key in config.GetSectionKeys(DailySection))
        {
            if (!int.TryParse(key, NumberStyles.None, CultureInfo.InvariantCulture, out int day)) continue;
            double time = (double)config.GetValue(DailySection, key, 0);
            if (time > 0) dailyTimes[day] = time;
        }
    }

    static double Faster(double oldTime, double newTime) => oldTime > 0 ? Math.Min(oldTime, newTime) : newTime;
    static string ChartKey(BoatKind boat, Charter charter) => $"{boat}_{charter}";

    void Save()
    {
        var config = new ConfigFile();
        config.SetValue(Section, "silver", Silver);
        config.SetValue(Section, "voyages", Voyages);
        config.SetValue(Section, "wins", Wins);
        config.SetValue(Section, "chain", BestChain);
        config.SetValue(Section, "kills", BestKills);
        config.SetValue(Section, "charters", charters);
        config.SetValue(Section, "muted", Muted);
        config.SetValue(Section, "lit_beacon", HasLitBeacon);
        config.SetValue(SailSection, "owned", sails);
        config.SetValue(SailSection, "equipped", (int)Livery);
        foreach (var entry in hunts)
        {
            string key = ChartKey(entry.Key.Boat, entry.Key.Charter);
            config.SetValue(ChartSection, key, entry.Value.Time);
            if (entry.Value.Seed != 0) config.SetValue(SeedSection, key, (long)entry.Value.Seed);
        }
        foreach (var entry in dailyTimes)
            config.SetValue(DailySection, entry.Key.ToString(CultureInfo.InvariantCulture), entry.Value);
        var error = config.Save(PendingPath);
        if (error == Error.Ok) error = DirAccess.RenameAbsolute(PendingPath, Path);
        if (error != Error.Ok) GD.PushWarning($"Captain’s log could not be saved ({error}).");
    }
}
