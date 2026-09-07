using Godot;

namespace CozySora;

[GlobalClass]
public partial class CozyWaterProfile : Resource
{
    [Export] public float Amplitude { get; set; } = .55f;
    [Export] public float WavelengthScale { get; set; } = 1;
    [Export] public float Swell { get; set; } = .35f;
    [Export] public float Wind { get; set; } = .3f;
    [Export] public float RippleStrength { get; set; } = 1;
    [Export] public float Roughness { get; set; } = .155f;
    [Export] public float MinimumOpticalDepth { get; set; } = 1.65f;
    [Export] public float ShoreDampingDepth { get; set; } = 2;
    [Export] public float FoamStrength { get; set; } = .4f;
    [Export] public Color DeepColor { get; set; } = new("18496f");
    [Export] public Color ScatterColor { get; set; } = new("29767e");
    [Export] public Vector3 Absorption { get; set; } = new(.56f, .185f, .072f);
}
