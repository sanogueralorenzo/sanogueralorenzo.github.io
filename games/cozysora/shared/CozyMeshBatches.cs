using Godot;

namespace CozySora;

/// <summary>Stable spatial grouping and local transforms preserve the existing visibility bounds.</summary>
public static class CozyMeshBatches
{
    public static Dictionary<Vector2I, List<Transform3D>> Cells(IReadOnlyList<Transform3D> transforms, float cellSize)
    {
        var result = new Dictionary<Vector2I, List<Transform3D>>();
        foreach (var transform in transforms)
        {
            var cell = new Vector2I(Mathf.FloorToInt(transform.Origin.X / cellSize), Mathf.FloorToInt(transform.Origin.Z / cellSize));
            if (!result.TryGetValue(cell, out var group)) result.Add(cell, group = new());
            group.Add(transform);
        }
        return result;
    }

    public static MultiMeshInstance3D Instances(Node3D parent, Mesh mesh, Material material,
        IReadOnlyList<Transform3D> transforms, Vector3 origin, string label, float rangeEnd = 0, float margin = 0,
        GeometryInstance3D.ShadowCastingSetting shadows = GeometryInstance3D.ShadowCastingSetting.On)
    {
        var multimesh = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D, Mesh = mesh, InstanceCount = transforms.Count };
        for (int i = 0; i < transforms.Count; i++)
        {
            var transform = transforms[i];
            transform.Origin -= origin;
            multimesh.SetInstanceTransform(i, transform);
        }
        var node = new MultiMeshInstance3D
        {
            Name = label,
            Multimesh = multimesh,
            MaterialOverride = material,
            Position = origin,
            VisibilityRangeEnd = rangeEnd,
            VisibilityRangeEndMargin = margin,
            CastShadow = shadows
        };
        parent.AddChild(node);
        return node;
    }

    public static int Spatial(Node3D parent, Mesh mesh, Material material, IReadOnlyList<Transform3D> transforms,
        string label, float cellSize, float rangeEnd = 0, float margin = 0,
        GeometryInstance3D.ShadowCastingSetting shadows = GeometryInstance3D.ShadowCastingSetting.On,
        float shadowRange = 0, float shadowMargin = 0)
    {
        var groups = Cells(transforms, cellSize);
        foreach (var (cell, group) in groups)
        {
            var origin = new Vector3(cell.X * cellSize + cellSize / 2, 0, cell.Y * cellSize + cellSize / 2);
            var node = Instances(parent, mesh, material, group, origin, label, rangeEnd, margin, shadows);
            if (shadowRange <= 0) continue;
            parent.AddChild(new MultiMeshInstance3D
            {
                Name = "Nearby grass shadows",
                Multimesh = node.Multimesh,
                MaterialOverride = material,
                Position = origin,
                CastShadow = GeometryInstance3D.ShadowCastingSetting.ShadowsOnly,
                VisibilityRangeEnd = shadowRange,
                VisibilityRangeEndMargin = shadowMargin
            });
        }
        return groups.Count;
    }

    private sealed record Bucket(SurfaceTool Surface, Material Material);

    public static void MergeStatic(Node3D parent, IReadOnlyCollection<Node> excluded, float cellSize = 32)
    {
        var buckets = new Dictionary<(ulong, Vector2I), Bucket>();
        CollectStatic(parent, Transform3D.Identity, excluded, cellSize, buckets);
        foreach (var entry in buckets.Values)
            parent.AddChild(new MeshInstance3D { Name = "SettlementBatch", Mesh = entry.Surface.Commit(), MaterialOverride = entry.Material });
    }

    private static void CollectStatic(Node3D node, Transform3D relative, IReadOnlyCollection<Node> excluded,
        float cellSize, Dictionary<(ulong, Vector2I), Bucket> buckets)
    {
        foreach (Node child in node.GetChildren())
        {
            if (child is not Node3D spatial || excluded.Contains(child)) continue;
            var transform = relative * spatial.Transform;
            if (child is MeshInstance3D instance && instance.Mesh is { } mesh)
            {
                if (instance.MaterialOverride is not { } material) continue;
                var cell = new Vector2I(Mathf.FloorToInt(transform.Origin.X / cellSize), Mathf.FloorToInt(transform.Origin.Z / cellSize));
                var key = (material.GetInstanceId(), cell);
                if (!buckets.TryGetValue(key, out var bucket))
                {
                    var surface = new SurfaceTool();
                    surface.Begin(Mesh.PrimitiveType.Triangles);
                    buckets.Add(key, bucket = new(surface, material));
                }
                for (int i = 0; i < mesh.GetSurfaceCount(); i++) bucket.Surface.AppendFrom(mesh, i, transform);
                // Collision shapes are siblings; labels and excluded animation roots survive.
                child.QueueFree();
            }
            else CollectStatic(spatial, transform, excluded, cellSize, buckets);
        }
    }
}
