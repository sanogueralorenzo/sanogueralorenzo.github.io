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

    public async Task Install(Node3D parent)
    {
        var env = new Environment
        {
            BackgroundMode = Environment.BGMode.Sky,
            Sky = new Sky { RadianceSize = Sky.RadianceSizeEnum.Size512 },
            AmbientLightSource = Environment.AmbientSource.Sky,
            AmbientLightSkyContribution = .68f,
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
        if (DisplayServer.GetName() != "headless")
            env.Sky.SkyMaterial = await BakeSky(parent, sun.GlobalBasis.Z.Normalized());
        if (FillEnergy > 0)
        {
            var fill = new DirectionalLight3D { LightColor = FillColor, LightEnergy = FillEnergy };
            parent.AddChild(fill);
            fill.Position = FillPosition;
            fill.LookAt(Vector3.Zero);
        }
        var water = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/ocean.gdshader") };
        if (env.Sky.SkyMaterial is PanoramaSkyMaterial daylight)
            water.SetShaderParameter("sky_panorama", daylight.Panorama);
        water.SetShaderParameter("sun_direction", sun.GlobalBasis.Z.Normalized());
        CozyPrimitives.Instance(parent, new PlaneMesh { Size = OceanSize }, OceanPosition, water);
    }

    private static async Task<PanoramaSkyMaterial> BakeSky(Node3D parent, Vector3 sunlight)
    {
        const int size = 96;
        using var noise = new FastNoiseLite
        {
            Seed = 7319, NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin, Frequency = .057f,
            FractalOctaves = 4, FractalGain = .52f
        };
        var slices = noise.GetSeamlessImage3D(size, size, size);
        var volume = new ImageTexture3D();
        volume.Create(slices[0].GetFormat(), size, size, size, false, slices);
        var clouds = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/sky.gdshader") };
        clouds.SetShaderParameter("cloud_noise", volume);
        clouds.SetShaderParameter("sun_direction", sunlight);
        var viewport = new SubViewport
        {
            Size = new(2048, 1024), Disable3D = true, UseHdr2D = true, World2D = new World2D(),
            RenderTargetUpdateMode = SubViewport.UpdateMode.Once
        };
        parent.AddChild(viewport);
        viewport.AddChild(new ColorRect { Size = viewport.Size, Material = clouds });
        await parent.ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
        using var panorama = viewport.GetTexture().GetImage();
        panorama.GenerateMipmaps();
        var sky = new PanoramaSkyMaterial { Panorama = ImageTexture.CreateFromImage(panorama) };
        viewport.QueueFree();
        return sky;
    }
}
