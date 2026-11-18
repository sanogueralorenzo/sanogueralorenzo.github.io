using Godot;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

// Central coordinate conversion; simulation retains its own units.
public partial class NativeStage3D : Node3D
{
    public const float Unit = .01f, Zoom = .70f, Foreshortening = .78f;
    public Camera3D Lens { get; private set; } = null!;
    ShaderMaterial water = null!;
    readonly Vector4[] whirlpools = new Vector4[32];
    MeshInstance3D sea = null!;
    Godot.Environment environment = null!;
    DirectionalLight3D sun = null!;
    Vector2 weather;
    float waveClock, previousClock;
    Vector3 middayRotation;
    static readonly Color SunDay = new("fff0d6"), SunAmber = new("ffc18b"), SunStorm = new("ead3c7");
    static readonly Color SkyDay = new("bfd3d6"), SkyAmber = new("c4b5c7"), SkyStorm = new("a9b6de");
    public static Vector3 Point(V2 p, float height = 0) => new(p.X * Unit, height, p.Y * Unit);
    public override void _Ready()
    {
        GetViewport().Msaa3D = Viewport.Msaa.Msaa4X;
        environment = new Godot.Environment
        {
            BackgroundMode = Godot.Environment.BGMode.Color, BackgroundColor = new("086b7f"),
            AmbientLightSource = Godot.Environment.AmbientSource.Color,
            AmbientLightColor = SkyDay, AmbientLightEnergy = .63f,
            ReflectedLightSource = Godot.Environment.ReflectionSource.Disabled,
            TonemapMode = Godot.Environment.ToneMapper.Linear,
            SsaoEnabled = true, SsaoRadius = .18f, SsaoIntensity = .65f,
            SsaoPower = 1.1f, SsaoDetail = .25f, SsaoLightAffect = .3f
        };
        AddChild(new WorldEnvironment { Environment = environment });
        sun = new DirectionalLight3D
        {
            LightColor = SunDay, LightEnergy = 1.08f, ShadowEnabled = true,
            DirectionalShadowMaxDistance = 65, DirectionalShadowMode = DirectionalLight3D.ShadowMode.Orthogonal,
            ShadowBlur = 2, ShadowBias = .025f, ShadowNormalBias = .4f
        };
        AddChild(sun); sun.Position = new(-18, 25, -12); sun.LookAt(Vector3.Zero);
        middayRotation = sun.Rotation;
        Lens = new Camera3D { Projection = Camera3D.ProjectionType.Orthogonal, KeepAspect = Camera3D.KeepAspectEnum.Height, Near = .1f, Far = 100, Current = true };
        AddChild(Lens);
        water = new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/native-water.gdshader") };
        sea = new MeshInstance3D { Mesh = new PlaneMesh { Size = new(160, 160) }, MaterialOverride = water, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
        AddChild(sea); Follow(Vector2.Zero);
    }
    public void Follow(Vector2 center, float sizeOverride = 0)
    {
        var target = new Vector3(center.X * Unit, 0, center.Y * Unit);
        Lens.Size = sizeOverride > 0 ? sizeOverride : GetViewport().GetVisibleRect().Size.Y / (Zoom / Unit);
        Lens.Position = target + new Vector3(0, Foreshortening * 32, Mathf.Sqrt(1 - Foreshortening * Foreshortening) * 32);
        Lens.LookAt(target); sea.Position = target;
        water.SetShaderParameter("sea_center", new Vector2(target.X, target.Z));
    }
    public void SetWhirlpools(System.Collections.Generic.IEnumerable<Whirlpool3D> surfaces)
    {
        int count = 0;
        foreach (var vortex in surfaces)
        {
            if (count == whirlpools.Length) break; // The streamed world holds at most 25 chunks.
            var p = vortex.GlobalPosition;
            whirlpools[count++] = new(p.X, p.Z, vortex.Radius * Whirlpool3D.WaterCutout, 0);
        }
        water.SetShaderParameter("whirlpools", whirlpools);
        water.SetShaderParameter("whirlpool_count", count);
    }
    public void Advance(float clock, float dt, float amber = 0, float storm = 0)
    {
        weather = weather.Lerp(new(amber, storm), 1 - Mathf.Exp(-dt * .78f));
        float evening = weather.X, cloud = weather.Y;
        if (clock < previousClock) { waveClock = 0; previousClock = 0; }
        waveClock += (clock - previousClock) * Mathf.Lerp(1, 1.92f, cloud);
        previousClock = clock;
        water.SetShaderParameter("clock", waveClock);
        water.SetShaderParameter("weather", weather);
        sun.LightColor = SunDay.Lerp(SunAmber, evening).Lerp(SunStorm, cloud);
        sun.LightEnergy = Mathf.Lerp(Mathf.Lerp(1.08f, .96f, evening), .78f, cloud);
        float lowSun = evening * (1 - cloud);
        sun.Rotation = middayRotation + new Vector3(.31f * lowSun, -.18f * lowSun, 0);
        environment.AmbientLightColor = SkyDay.Lerp(SkyAmber, evening).Lerp(SkyStorm, cloud);
        DioramaSurface.Advance(clock);
        EnvironmentArt3D.Advance(waveClock, weather);
        Whirlpool3D.Advance(waveClock, weather);
    }
    public Vector2 Screen(V2 p, float height = 0) => Lens.UnprojectPosition(Point(p, height));
    public V2 WorldPoint(Vector2 screen)
    {
        var origin = Lens.ProjectRayOrigin(screen); var direction = Lens.ProjectRayNormal(screen);
        var hit = origin - direction * (origin.Y / direction.Y);
        return new(hit.X / Unit, hit.Z / Unit);
    }
}
