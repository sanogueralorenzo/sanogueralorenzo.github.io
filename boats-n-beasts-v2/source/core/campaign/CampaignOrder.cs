namespace BoatsNBeasts.Core;

public enum SeaDuty { Convoy, Salvage, Hunt, Sounding, Blockade, Landing }

public sealed record CampaignOrder(string Id, string Region, string Title, string Brief, string Objective,
    string Boss, string Homecoming, SeaDuty Duty, int Tier, int Legs)
{
    public LandingStep[]? LandingSteps { get; init; }
    public SeaJob[]? SeaStations { get; init; }
    public string Island { get; init; } = "";
    public CaseEvidence? Evidence { get; init; }
    public bool PrizeWatch { get; init; }
    public bool Underways { get; init; }
    public bool Postal { get; init; }
    public bool Migration { get; init; }
    public bool Pilotage { get; init; }
    public bool Ashore => Duty == SeaDuty.Landing;
}
