using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

sealed class CaptainLog
{
    const string Path = "user://captain.cfg";
    const string Section = "log";
    public int Silver { get; private set; }
    public int Voyages { get; private set; }
    public int Wins { get; private set; }
    public int BestChain { get; private set; }
    public int BestKills { get; private set; }
    public double FastestSeconds { get; private set; }
    public bool Muted { get; private set; }
    int charters = 1;

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

    public void Earn(int amount)
    {
        Silver += amount;
        Save();
    }

    public void Record(Voyage run)
    {
        Voyages++;
        BestKills = Math.Max(BestKills, run.Kills);
        BestChain = Math.Max(BestChain, run.LongestChain);
        if (run.BossSlain)
        {
            Wins++;
            FastestSeconds = FastestSeconds == 0 ? run.CombatTime : Math.Min(FastestSeconds, run.CombatTime);
        }
        Save();
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
        FastestSeconds = (double)config.GetValue(Section, "fastest", 0);
        charters = (int)config.GetValue(Section, "charters", 1);
        Muted = (bool)config.GetValue(Section, "muted", false);
    }

    void Save()
    {
        var config = new ConfigFile();
        config.SetValue(Section, "silver", Silver);
        config.SetValue(Section, "voyages", Voyages);
        config.SetValue(Section, "wins", Wins);
        config.SetValue(Section, "chain", BestChain);
        config.SetValue(Section, "kills", BestKills);
        config.SetValue(Section, "fastest", FastestSeconds);
        config.SetValue(Section, "charters", charters);
        config.SetValue(Section, "muted", Muted);
        config.Save(Path);
    }
}
