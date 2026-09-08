using Godot;

namespace Further.Salvage;

/// <summary>Geometry resources and instances; callers own dimensions and tessellation.</summary>
public static class CozyPrimitives
{
    public static BoxMesh BoxMesh(Vector3? size = null) => new() { Size = size ?? Vector3.One };

    public static CylinderMesh CylinderMesh(float bottom, float top, float height, int segments = 10) => new()
    {
        BottomRadius = bottom,
        TopRadius = top,
        Height = height,
        RadialSegments = segments
    };

    public static SphereMesh SphereMesh(float radius = .5f, float height = 1f, int segments = 10, int rings = 5) => new()
    {
        Radius = radius,
        Height = height,
        RadialSegments = segments,
        Rings = rings
    };

    public static MeshInstance3D Instance(Node3D parent, Mesh mesh, Vector3 position, Material material, Vector3? size = null)
    {
        var node = new MeshInstance3D
        {
            Mesh = mesh,
            MaterialOverride = material,
            Position = position,
            Scale = size ?? Vector3.One
        };
        parent.AddChild(node);
        return node;
    }

    public static MeshInstance3D Box(Node3D parent, Vector3 position, Vector3 size, Material material)
    {
        var node = Instance(parent, BoxMesh(size), position, material);
        return node;
    }

    public static MeshInstance3D Cylinder(Node3D parent, Vector3 position, float bottom, float top, float height, Material material)
        => Instance(parent, CylinderMesh(bottom, top, height), position, material);

    public static MeshInstance3D Sphere(Node3D parent, Vector3 position, Vector3 size, Material material)
        => Instance(parent, SphereMesh(1, 2), position, material, size);

    public static MeshInstance3D Beam(Node3D parent, Vector3 start, Vector3 end, float radius, Material material)
    {
        var node = Cylinder(parent, (start + end) / 2, radius, radius, start.DistanceTo(end), material);
        node.Quaternion = new Quaternion(Vector3.Up, (end - start).Normalized());
        return node;
    }
}
