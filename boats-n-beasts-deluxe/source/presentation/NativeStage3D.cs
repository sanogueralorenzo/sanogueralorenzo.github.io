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
    float storm;
    public static Vector3 Point(V2 p, float height = 0) => new(p.X * Unit, height, p.Y * Unit);
    public override void _Ready()
    {
        GetViewport().Msaa3D = Viewport.Msaa.Msaa4X;
        environment = new Godot.Environment
        {
            BackgroundMode = Godot.Environment.BGMode.Color, BackgroundColor = new("086b7f"),
            AmbientLightSource = Godot.Environment.AmbientSource.Color,
            AmbientLightColor = new("bfd3d6"), AmbientLightEnergy = .63f,
            ReflectedLightSource = Godot.Environment.ReflectionSource.Disabled,
            TonemapMode = Godot.Environment.ToneMapper.Linear,
            SsaoEnabled = true, SsaoRadius = .18f, SsaoIntensity = .65f,
            SsaoPower = 1.1f, SsaoDetail = .25f, SsaoLightAffect = .3f
        };
        AddChild(new WorldEnvironment { Environment = environment });
        sun = new DirectionalLight3D
        {
            LightColor = new("ffe4bc"), LightEnergy = 1.08f, ShadowEnabled = true,
            DirectionalShadowMaxDistance = 65, DirectionalShadowMode = DirectionalLight3D.ShadowMode.Orthogonal,
            ShadowBlur = 2, ShadowBias = .025f, ShadowNormalBias = .4f
        };
        AddChild(sun); sun.Position = new(-18, 25, -12); sun.LookAt(Vector3.Zero);
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
    public void Advance(float clock, float stormTarget = 0, float dt = 0)
    {
        storm = Mathf.Lerp(storm, stormTarget, 1 - Mathf.Exp(-dt * .85f));
        water.SetShaderParameter("clock", clock);
        water.SetShaderParameter("storm", storm);
        sun.LightColor = new Color("ffe4bc").Lerp(new Color("ffe0b9"), storm);
        sun.LightEnergy = Mathf.Lerp(1.08f, .77f, storm);
        environment.AmbientLightColor = new Color("bfd3d6").Lerp(new Color("a8b8db"), storm);
        DioramaSurface.Advance(clock);
        EnvironmentArt3D.Advance(clock);
        Whirlpool3D.Advance(clock);
    }
    public Vector2 Screen(V2 p, float height = 0) => Lens.UnprojectPosition(Point(p, height));
    public V2 WorldPoint(Vector2 screen)
    {
        var origin = Lens.ProjectRayOrigin(screen); var direction = Lens.ProjectRayNormal(screen);
        var hit = origin - direction * (origin.Y / direction.Y);
        return new(hit.X / Unit, hit.Z / Unit);
    }
}
