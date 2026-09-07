using Godot;
using Environment = Godot.Environment;

namespace CozySora;

[GlobalClass]
public partial class CozyAtmosphere : Resource
{
    [Export] public Color AmbientColor { get; set; } = new("a4b2bc");
    [Export] public float AmbientEnergy { get; set; } = .48f;
    [Export] public Color FogColor { get; set; } = new("c9d6de");
    [Export] public float FogBegin { get; set; } = 40;
    [Export] public float FogEnd { get; set; } = 260;
    [Export] public float FogCurve { get; set; } = 1;
    [Export] public float FogSky { get; set; } = .1f;
    [Export] public Color SunColor { get; set; } = new("ffdfb6");
    [Export] public float SunEnergy { get; set; } = 1.32f;
    [Export] public float ShadowDistance { get; set; } = 110;
    [Export] public float ShadowNormalBias { get; set; } = .35f;
    [Export] public Vector3 SunPosition { get; set; } = new(-66, 84, -45.6f);
    [Export] public Vector3 SunRotationDegrees { get; set; }
    [Export] public bool AimSunAtOrigin { get; set; } = true;
    [Export] public Color FillColor { get; set; } = new("c9d6ec");
    [Export] public float FillEnergy { get; set; } = .16f;
    [Export] public Vector3 FillPosition { get; set; } = new(60, 50, 90);
    [Export] public Vector2 OceanSize { get; set; } = new(4000, 4000);
    [Export] public Vector3 OceanPosition { get; set; } = new(0, -30, 0);
    [Export] public bool OceanEnabled { get; set; } = true;
    [Export] public CozyWaterProfile? WaterProfile { get; set; }
    [Export] public float BrushRadius { get; set; } = 2;

    public void Install(Node3D parent)
    {
        var env = new Environment
        {
            BackgroundMode = Environment.BGMode.Sky,
            Sky = new Sky { SkyMaterial = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/sky.gdshader") } },
            AmbientLightSource = Environment.AmbientSource.Color,
            AmbientLightColor = AmbientColor,
            AmbientLightEnergy = AmbientEnergy,
            TonemapMode = Environment.ToneMapper.Filmic,
            TonemapExposure = 1,
            SsaoEnabled = true,
            SsaoRadius = .75f,
            SsaoIntensity = .8f,
            SsaoPower = 1.3f,
            SsaoDetail = .6f,
            FogEnabled = true,
            FogMode = Environment.FogModeEnum.Depth,
            FogLightColor = FogColor,
            FogDepthBegin = FogBegin,
            FogDepthEnd = FogEnd,
            FogDepthCurve = FogCurve,
            FogSkyAffect = FogSky
        };
        parent.AddChild(new WorldEnvironment { Environment = env });
        var sun = new DirectionalLight3D
        {
            Name = "SummerSun",
            LightColor = SunColor,
            LightEnergy = SunEnergy,
            ShadowEnabled = true,
            DirectionalShadowMaxDistance = ShadowDistance,
            DirectionalShadowMode = DirectionalLight3D.ShadowMode.Parallel2Splits,
            DirectionalShadowSplit1 = .16f,
            DirectionalShadowBlendSplits = true,
            ShadowBlur = 2,
            ShadowBias = .1f,
            ShadowNormalBias = ShadowNormalBias
        };
        parent.AddChild(sun);
        if (AimSunAtOrigin) { sun.Position = SunPosition; sun.LookAt(Vector3.Zero); }
        else sun.RotationDegrees = SunRotationDegrees;
        if (FillEnergy > 0)
        {
            var fill = new DirectionalLight3D { LightColor = FillColor, LightEnergy = FillEnergy };
            parent.AddChild(fill);
            fill.Position = FillPosition;
            fill.LookAt(Vector3.Zero);
        }
        if (parent is CozyMap map)
        {
            map.Atmosphere = this;
            if (OceanEnabled)
                CozyWaterSurface.Create(map, new Rect2(new Vector2(OceanPosition.X, OceanPosition.Z) - OceanSize * .5f, OceanSize),
                    OceanPosition.Y, map.HeightAt, WaterProfile ?? new CozyWaterProfile(), this, true);
        }
    }

    public void InstallPost(Node parent)
    {
        var layer = new CanvasLayer { Layer = -1 };
        var rect = new ColorRect { MouseFilter = Control.MouseFilterEnum.Ignore };
        rect.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var effect = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/paint.gdshader") };
        effect.SetShaderParameter("brush_radius", BrushRadius);
        rect.Material = effect;
        layer.AddChild(rect);
        parent.AddChild(layer);
    }
}
