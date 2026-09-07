using Godot;

namespace CozySora;

/// <summary>Godot adapter for anchored props following the shared surface.</summary>
public partial class CozyWaterFloat : Node
{
    private Node3D _body = null!;
    private CozyWaterSurface _water = null!;
    private Vector3 _anchor;
    private float _offset;

    public static void Attach(Node3D body, CozyWaterSurface water, float offset = .25f)
    {
        var follower = new CozyWaterFloat { _body = body, _water = water, _anchor = body.GlobalPosition, _offset = offset, ProcessPhysicsPriority = -10 };
        body.AddChild(follower);
        follower.Follow(1);
    }

    public override void _PhysicsProcess(double delta) => Follow(1 - Mathf.Exp(-(float)delta * 5));

    private void Follow(float blend)
    {
        float height = _water.HeightAt(_anchor.X, _anchor.Z);
        if (!float.IsFinite(height)) return;
        const float footprint = 1.5f;
        float dx = (_water.HeightAt(_anchor.X + footprint, _anchor.Z) - _water.HeightAt(_anchor.X - footprint, _anchor.Z)) / (2 * footprint);
        float dz = (_water.HeightAt(_anchor.X, _anchor.Z + footprint) - _water.HeightAt(_anchor.X, _anchor.Z - footprint)) / (2 * footprint);
        if (!float.IsFinite(dx) || !float.IsFinite(dz)) return;
        _body.GlobalPosition = _body.GlobalPosition.Lerp(new(_anchor.X, height + _offset, _anchor.Z), blend);
        var normal = new Vector3(-dx, 1, -dz).Normalized();
        var tilt = new Quaternion(Vector3.Up, normal);
        _body.Quaternion = _body.Quaternion.Slerp(tilt, blend);
    }
}
