using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public abstract partial class CrewRun : Node
{
    public Action<bool,int>? Returned;
    public int Seed { get; set; } = Random.Shared.Next();
    public BoatKind Vessel { get; set; }
    public int Figurehead { get; set; } = -1;
    public Loadout Outfit { get; set; }
    public int Stores { get; set; }
    public int CarriedSilver { get; set; }
    public string LandingName { get; set; } = "Last Light Quay";
    public virtual CrewRun? ActiveWatch=>null;
    public CrewRun InPlay=>ActiveWatch?.InPlay??this;
    public virtual bool AskShipmate(Shipmate mate) => false;
    public int SilverAboard=>CarriedSilver+SilverEarned;
    public abstract int SilverEarned { get; }
}
