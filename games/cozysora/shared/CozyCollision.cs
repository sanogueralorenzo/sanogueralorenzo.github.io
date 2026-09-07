using Godot;

namespace CozySora;

public static class CozyCollision
{
    public static CollisionShape3D Box(PhysicsBody3D body, Vector3 position, Vector3 size, Vector3 rotation = default)
    {
        var shape = new CollisionShape3D { Shape = new BoxShape3D { Size = size }, Position = position, Rotation = rotation };
        body.AddChild(shape);
        return shape;
    }

    public static StaticBody3D StaticBox(Node3D parent, Vector3 position, Vector3 size)
    {
        var body = new StaticBody3D { Position = position };
        Box(body, Vector3.Zero, size);
        parent.AddChild(body);
        return body;
    }

    public static CollisionShape3D Mesh(PhysicsBody3D body, Mesh geometry)
    {
        var shape = new CollisionShape3D { Shape = geometry.CreateTrimeshShape() };
        body.AddChild(shape);
        return shape;
    }

    public static void Limb(PhysicsBody3D body, Vector3 start, Vector3 end, float radius)
    {
        var shape = new CollisionShape3D
        {
            Shape = new CapsuleShape3D { Radius = radius, Height = Mathf.Max(radius * 2, start.DistanceTo(end)) },
            Position = (start + end) * .5f,
            Rotation = new Quaternion(Vector3.Up, (end - start).Normalized()).GetEuler()
        };
        body.AddChild(shape);
    }
}
