using Godot;

namespace CozySora;

public readonly record struct CozySpawn(Vector3 Position, float Yaw = 0, float Pitch = .09f, string Mode = "cat");

[GlobalClass]
public partial class CozyMapDefinition : Resource
{
    [Export] public StringName Id { get; set; } = "";
    [Export] public string Title { get; set; } = "";
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = "";
    [Export] public string Subtitle { get; set; } = "";
    [Export(PropertyHint.File, "*.tscn")] public string Scene { get; set; } = "";
    [Export] public Texture2D? Preview { get; set; }
    [Export] public Vector3 SpawnPosition { get; set; }
    [Export] public float SpawnYaw { get; set; }
    [Export] public float SpawnPitch { get; set; } = .09f;
    [Export(PropertyHint.Enum, "cat,gull")] public string SpawnMode { get; set; } = "cat";
    public CozySpawn Spawn() => new(SpawnPosition, SpawnYaw, SpawnPitch, SpawnMode);
}
