using Godot;

namespace CozySora;

/// <summary>Small cream butterflies and drifting pollen above the opening verge.</summary>
public partial class SeabreezeSummerLife : Node3D
{
    private sealed record Butterfly(Node3D Body, Node3D[] Wings, Vector2 Home, float Phase, float Speed);
    private readonly List<Butterfly> _creatures = new();
    private CozyMap _world = null!;
    private double _clock = 3;

    public void Build(CozyMap world)
    {
        _world = world;
        var random = new RandomNumberGenerator { Seed = 99 };
        var cream = new StandardMaterial3D { AlbedoColor = new("fff3c0"), ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded, CullMode = BaseMaterial3D.CullModeEnum.Disabled };
        Vector2[] patches = [new(-3.3f, -4.6f), new(-3, -6.2f), new(-3.4f, -3.4f), new(-1.5f, -5.5f), new(-10, 0)];
        for (int i = 0; i < 70; i++)
        {
            var patch = patches[random.RandiRange(0, 4)];
            var home = patch + new Vector2(random.RandfRange(-2, 2), random.RandfRange(-2, 2));
            var body = new Node3D();
            AddChild(body);
            Node3D[] wings = new Node3D[2];
            for (int j = 0; j < 2; j++)
            {
                var wing = new Node3D();
                body.AddChild(wing);
                wing.AddChild(new MeshInstance3D { Mesh = new PrismMesh { Size = new(.075f, .006f, .058f) }, MaterialOverride = cream, Position = new((j * 2 - 1) * .038f, 0, 0) });
                wings[j] = wing;
            }
            _creatures.Add(new(body, wings, home, random.Randf() * 100, random.RandfRange(.6f, 1.2f)));
        }
        GD.Load<CozyAirParticles>("res://maps/seabreeze_village/air.tres").Install(this, new(-6, 4, -1));
    }

    public override void _Process(double delta)
    {
        _clock += delta;
        foreach (var creature in _creatures)
        {
            double t = _clock * creature.Speed + creature.Phase;
            float x = creature.Home.X + (float)Math.Sin(t * .7) * .6f;
            float z = creature.Home.Y + (float)Math.Cos(t * .5) * .6f;
            creature.Body.Position = new(x, _world.HeightAt(x, z) + .6f + (float)Math.Sin(t) * .3f, z);
            creature.Body.Rotation = new(.4f, (float)t * .5f, (float)Math.Sin(t * 2) * .3f);
            float flap = (float)Math.Sin(_clock * 22 + creature.Phase) * .9f;
            creature.Wings[0].Rotation = new(0, 0, flap);
            creature.Wings[1].Rotation = new(0, 0, -flap);
        }
    }
}
