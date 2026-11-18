using Godot;

namespace CozySora;

[GlobalClass]
public partial class CozyAirParticles : Resource
{
    [Export] public int Amount { get; set; } = 80;
    [Export] public double Lifetime { get; set; } = 14;
    [Export] public Aabb Bounds { get; set; } = new(new(-30, -2, -25), new(60, 18, 50));
    [Export] public Vector3 Extents { get; set; } = new(22, 4, 20);
    [Export] public Vector3 Direction { get; set; } = new(.8f, -.1f, .6f);
    [Export] public float Spread { get; set; } = 20;
    [Export] public Vector2 Velocity { get; set; } = new(.1f, .35f);
    [Export] public Vector3 Gravity { get; set; }
    [Export] public Vector2 ParticleScale { get; set; } = new(.012f, .027f);
    [Export] public float Radius { get; set; } = .5f;
    [Export] public float Height { get; set; } = 1;
    [Export] public int Segments { get; set; } = 4;
    [Export] public int Rings { get; set; } = 2;
    [Export] public Color Color { get; set; } = new("fff3c0");
    [Export] public bool DoubleSided { get; set; } = true;
    [Export] public bool CastShadows { get; set; } = true;

    public GpuParticles3D Install(Node3D parent, Vector3 position)
    {
        var motion = new ParticleProcessMaterial
        {
            EmissionShape = ParticleProcessMaterial.EmissionShapeEnum.Box,
            EmissionBoxExtents = Extents,
            Direction = Direction,
            Spread = Spread,
            InitialVelocityMin = Velocity.X,
            InitialVelocityMax = Velocity.Y,
            Gravity = Gravity,
            ScaleMin = ParticleScale.X,
            ScaleMax = ParticleScale.Y
        };
        var material = new StandardMaterial3D { AlbedoColor = Color, ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded };
        if (DoubleSided) material.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
        var mesh = CozyPrimitives.SphereMesh(Radius, Height, Segments, Rings);
        mesh.Material = material;
        var particles = new GpuParticles3D
        {
            Name = "Drifting summer air",
            Amount = Amount,
            Lifetime = Lifetime,
            Preprocess = Lifetime,
            VisibilityAabb = Bounds,
            Position = position,
            ProcessMaterial = motion,
            DrawPass1 = mesh
        };
        if (!CastShadows) particles.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        parent.AddChild(particles);
        return particles;
    }
}
