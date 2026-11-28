using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public abstract partial class CrewRun : Node
{
    public Action<bool,int>? Returned;
    public int Seed { get; set; } = Random.Shared.Next();
    public Loadout Outfit { get; set; }
    public int Stores { get; set; }
    public abstract int SilverEarned { get; }
}
