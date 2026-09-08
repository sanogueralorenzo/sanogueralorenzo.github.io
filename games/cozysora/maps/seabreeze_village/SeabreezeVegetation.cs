using Godot;

namespace CozySora;

public partial class SeabreezeVegetation : Node3D
{
    private SeabreezeWorld _world = null!;
    private readonly SeabreezeRandom _rng = new();
    private readonly SeabreezePlantMeshes _plants;
    private readonly List<SeabreezePlantMeshes.Plant> _trees = new(), _bushes = new();
    private readonly List<Vector3> _placed = new();
    private readonly List<List<Transform3D>> _tree_batches = new(), _bush_batches = new();
    private Texture2D[] _leaf_textures = [];
    private Texture2D _large_leaf_texture = null!, _pine_texture = null!;
    private Vector2 _flower_patch_center = new(float.PositiveInfinity, float.PositiveInfinity);
    private string _cache_path = "";
    public SeabreezeVegetation() => _plants = new(_rng);
    private async Task NextFrame() => await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
    private sealed record TreeOptions
    {
        public int Color { get; init; } = 4880954;
        public int Bark { get; init; } = 6969416;
        public int Clusters { get; init; } = 110;
        public float LeafLift { get; init; } = .1f;
        public float CardSize { get; init; } = 1.6f;
        public float ClusterRadius { get; init; } = 1.2f;
        public bool Shadow { get; init; } = true;
    }
    private sealed record MeadowOptions
    {
        public bool Force { get; init; }
        public float SeedHeads { get; init; }
        public float Width { get; init; } = 1;
        public Vector3? Base { get; init; }
        public Vector3? Mid { get; init; }
        public Vector3? Tip { get; init; }
    }
    private sealed record FlowerSet
    {
        public Color Color { get; init; }
        public float[][] Patches { get; init; } = [];
    }
    private sealed record RosetteGroup
    {
        public int Color { get; init; }
        public int Tip { get; init; }
        public float[][] Rows { get; init; } = [];
    }
    public async Task Build(SeabreezeWorld world)
    {
        _world = world;
        _cache_path = "user://foliage_" + world.GenerationSignature + ".scn";
        if (CozySceneCache.RestoreChildren(this, _cache_path))
        {
            GD.Print("Vegetation restored from procedural cache");
            return;
        }
        _rng.Seed = 777;
        _leaf_textures = new[] { SeabreezeTextures.LeafTexture(11), SeabreezeTextures.LeafTexture(23), SeabreezeTextures.LeafTexture(37, true) };
        _pine_texture = SeabreezeTextures.PineNeedleTexture();
        for (int i = 0; i < 6; i += 1)
        {
            _trees.Add(_plants.TreeMesh(i + 1, i == 2 || i == 4));
            _tree_batches.Add(new List<Transform3D>());
            await NextFrame();
        }
        for (int i = 0; i < 7; i += 1)
        {
            _bushes.Add(_plants.BushMesh(i));
            _bush_batches.Add(new List<Transform3D>());
            await NextFrame();
        }
        LandmarkFoliage();
        ForestDistribution();
        var palette = new[] { new Color("4c7a3a"), new Color("3f7a4a"), new Color("3c7052"), new Color("3f7a4a"), new Color("3c7052"), new Color("3f7a4a") };
        for (int i = 0; i < 6; i += 1)
        {
            var leaves = FoliageMaterial(_leaf_textures[i % 2], palette[i], 0.16f);
            Batch(_trees[i].Leaves, leaves, _tree_batches[i], $"Tree crowns {i}");
            Batch(_trees[i].Trunk!, SeabreezeTextures.BarkMaterial(), _tree_batches[i], $"Branching trunks {i}");
        }
        for (int i = 0; i < 7; i += 1)
        {
            var colors = new[] { new Color("5a7d34"), new Color("5a7d34"), new Color("9a9a38"), new Color("3d6e3c"), new Color("6a9340"), new Color("8a923c"), new Color("6a9340") };
            Batch(_bushes[i].Leaves, FoliageMaterial(_leaf_textures[(i >= 4 ? 2 : i % 2)], colors[i], 0.10f), _bush_batches[i], $"Hedges {i}");
        }
        _world.EmitSignal(CozyMap.SignalName.LoadProgress, "Planting the meadows…", .72f);
        await NextFrame();
        await GrassFields();
        Flowers();
        Rosettes();
        _world.EmitSignal(CozyMap.SignalName.LoadProgress, "Adding the last summer details…", .90f);
        await NextFrame();
        AreaFlora();
        GD.Print("Vegetation: ", _placed.Count, " trees and shrubs, procedural grass and flowers");
        CozySceneCache.Save(this, _cache_path);
    }
    private float Coast(float x)
    {
        return -0.0022f * x * x + 0.00001f * x * x * x;
    }
    private ShaderMaterial FoliageMaterial(Texture2D texture, Color color, float wind)
    {
        var material = new ShaderMaterial();
        material.Shader = GD.Load<Shader>("res://shaders/foliage.gdshader");
        material.SetShaderParameter("leaf_texture", texture);
        material.SetShaderParameter("tint", color);
        material.SetShaderParameter("wind_amplitude", wind);
        return material;
    }
    private void Batch(Mesh mesh, Material material, IReadOnlyList<Transform3D> transforms, string label, float range_end = 0)
    {
        var grass = label == "Wind grass";
        CozyMeshBatches.Spatial(this, mesh, material, transforms, label, 24, range_end, (range_end > 0 ? 10 : 0), (grass ? GeometryInstance3D.ShadowCastingSetting.Off : GeometryInstance3D.ShadowCastingSetting.On), (grass ? 28 : 0), (grass ? 6 : 0));
    }
    private bool ClearOfOther(float x, float z, float radius)
    {
        foreach (var p in _placed)
        {
            if (new Vector2(p.X - x, p.Z - z).LengthSquared() < Mathf.Pow(p.Y + radius, 2) * 0.22f)
            {
                return false;
            }
        }
        return true;
    }
    private void PlantTree(float x, float z, float scale_value, int kind, float crowd = 1, bool force = false, Vector3 special_scale = default, float yaw = -1)
    {
        float radius = _trees[kind].Radius * scale_value;
        if (!force)
        {
            if (_world.SurfaceAt(x, z) != "grass" || _world.Excluded(x, z) || _world.RoadInfo(x, z).D < 6.5f + scale_value)
            {
                return;
            }
            if (x > -11.5f && x < -1.3f && z - Coast(x) > -11 && z - Coast(x) < 9.5f)
            {
                return;
            }
            if (!ClearOfOther(x, z, radius * crowd))
            {
                return;
            }
        }
        float rotation = (yaw < 0 ? (float)_rng.Randf() * Mathf.Tau : yaw);
        var tilt = (force ? Vector3.Zero : new Vector3(_rng.RandfRange(-0.04f, 0.04f), 0, _rng.RandfRange(-0.04f, 0.04f)));
        var size = ((special_scale == Vector3.Zero ? ((force ? Vector3.One * scale_value : new Vector3(scale_value * _rng.RandfRange(0.9f, 1.1f), scale_value, scale_value * _rng.RandfRange(0.9f, 1.1f)))) : special_scale));
        var transform = new Transform3D((new Basis(Vector3.Up, rotation) * Basis.FromEuler(tilt)).Scaled(size), new Vector3(x, _world.HeightAt(x, z) - 0.15f, z));
        _tree_batches[kind].Add(transform);
        _placed.Add(new Vector3(x, radius, z));
        if (Mathf.Abs(x) < 110 && z < 100)
        {
            var body = new StaticBody3D();
            var shape = new CollisionShape3D();
            var cylinder = new CylinderShape3D();
            cylinder.Radius = 0.3f * scale_value + 0.15f;
            cylinder.Height = 3 * scale_value;
            shape.Shape = cylinder;
            shape.Position = new Vector3(shape.Position.X, cylinder.Height * 0.5f, shape.Position.Z);
            body.Position = transform.Origin;
            body.AddChild(shape);
            AddChild(body);
        }
    }
    private void PlantBush(float x, float z, float scale_value, int kind, float crowd = 0.6f, bool force = false, Vector3 special_scale = default, float yaw = -1)
    {
        float radius = _bushes[kind].Radius * scale_value;
        float local_z = z - Coast(x);
        bool layby = x > -9.6f && x < -3.2f && local_z > -9.1f && local_z < 7.6f;
        if ((!force && (_world.SurfaceAt(x, z) != "grass" || _world.Excluded(x, z, -2.8f) || layby || _world.RoadInfo(x, z).D < 5.2f || !ClearOfOther(x, z, radius * crowd))))
        {
            return;
        }
        float rotation = (yaw < 0 ? (float)_rng.Randf() * Mathf.Tau : yaw);
        var size = ((special_scale == Vector3.Zero ? new Vector3(scale_value, scale_value * _rng.RandfRange(0.85f, 1.15f), scale_value) : special_scale));
        // Compress only toward the route, retaining the long, layered verge behind it.
        // Project the rotated crown bounds and reserve room for wind, not just its center.
        Aabb bounds = _bushes[kind].Leaves.GetAabb();
        var road = _world.RoadInfo(x, z);
        var toward = new Vector3(-road.Tz, 0, road.Tx).Normalized();
        float room = road.D - 4.4f;
        var layby_room = (x < -9.6f ? -9.8f - x : x + 2.9f);
        if (local_z > -10 && local_z < 9 && (x < -9.6f || x > -3.2f) && layby_room < room)
        {
            room = layby_room;
            toward = Vector3.Right;
        }
        var basis = new Basis(Vector3.Up, rotation).Scaled(size);
        var extent = 0f;
        foreach (var ix in new float[] { bounds.Position.X, bounds.End.X })
        {
            foreach (var iz in new float[] { bounds.Position.Z, bounds.End.Z })
            {
                extent = Mathf.Max(extent, Mathf.Abs((basis * new Vector3(ix, 0, iz)).Dot(toward)));
            }
        }
        var pruning = Mathf.Clamp((room - .24f) / Mathf.Max(extent, .1f), .01f, 1f);
        size.Y *= Mathf.Lerp(.65f, 1f, pruning);
        foreach (var sign_position in new[] { new Vector2(-8.75f, 3.2f), new Vector2(-1, -17.05f), new Vector2(40, -17.1f + Coast(40)), new Vector2(-12.5f, -17.2f + Coast(-12.5f)) })
        {
            if (new Vector2(x, z).DistanceTo(sign_position) < radius + .7f)
            {
                float canopy_height = _bushes[kind].Leaves.GetAabb().End.Y;
                size.Y = Mathf.Min(size.Y, .9f / Mathf.Max(.1f, canopy_height));
            }
        }
        basis = new Basis(Vector3.Up, rotation).Scaled(size);
        for (int axis = 0; axis < 3; axis += 1)
        {
            basis[axis] -= toward * basis[axis].Dot(toward) * (1f - pruning);
        }
        _bush_batches[kind].Add(new Transform3D(basis, new Vector3(x, _world.HeightAt(x, z) - 0.2f, z)));
        _placed.Add(new Vector3(x, radius * 0.8f, z));
    }
    private void LandmarkFoliage()
    {
        PlantTree(-1.1f, -4, 1.45f, 1, 1, true, new Vector3(1.45f, 1.2f, 1.45f), 1.2f);
        _placed[^1] = new Vector3(-1.1f, 4, -4);
        PlantTree(-11.5f, -6.5f, 1, 3, 1, true, new Vector3(1, 0.85f, 1), 2.1f);
        _placed[^1] = new Vector3(-11.5f, 0.6f, -6.5f);
        PlantBush(-11, -5.4f, 1.3f, 6, 1, true, new Vector3(1.3f, 1.65f, 1.2f), 0.9f);
        _placed[^1] = new Vector3(-11, 2.4f, -5.4f);
        PlantBush(-10.1f, -7, 0.9f, 5, 1, true, new Vector3(0.9f, 1, 0.9f), 2.4f);
        _placed.RemoveAt(_placed.Count - 1);
        PlantTree(-15.5f, -5, 1.5f, 4, 1, true, Vector3.One * 1.5f, 0.8f);
        _placed[^1] = new Vector3(-15.5f, 0.6f, -5);
        PlantTree(-11, 1.5f, 1.7f, 2, 1, true, Vector3.One * 1.7f, 2.1f);
        _placed[^1] = new Vector3(-11, 0.6f, 1.5f);
        PlantTree(-7, -18.2f, 2, 3, 1, true, new Vector3(2.3f, 1.15f, 1.7f), 0);
        _placed[^1] = new Vector3(-7, 0.6f, -18.2f);
        foreach (var p in new[] { new Vector2(-13.5f, -18.4f), new Vector2(-16.5f, -18.6f), new Vector2(-19.5f, -18.8f) })
        {
            PlantBush(p.X, p.Y, 1.3f, 3, 0.1f);
        }
        foreach (var row in new[] { new float[] { -8, -17.8f, 1.2f, 6, 0.4f }, new float[] { -5, -17.95f, 1, 5, 1.7f }, new float[] { -1.8f, -17.85f, 1.15f, 6, 2.6f }, new float[] { 1.6f, -18, 0.95f, 4, 0.9f } })
        {
            PlantBush(row[0], row[1] + Coast(row[0]), row[2], (int)(row[3]), 1, true, Vector3.One * row[2], row[4]);
        }
        foreach (var row in new[] { new float[] { 34, -19.1f, 1.6f, 0 }, new float[] { 40, -19.3f, 1.8f, 2 }, new float[] { 46, -19, 1.5f, 0 }, new float[] { 56, -23.2f, 1.5f, 0 }, new float[] { 58.5f, -23, 1, 5 }, new float[] { 60.5f, -23.6f, 1.25f, 1 }, new float[] { 63, -23.5f, 0.95f, 0 }, new float[] { 65.5f, -23.3f, 1.5f, 5 }, new float[] { 70, -23.6f, 1.3f, 3 } })
        {
            PlantTree(row[0], row[1] + ((row[0] < 50 ? Coast(row[0]) : 0)), row[2], (int)(row[3]), 1, true);
        }
        for (int i = 0; i < 6; i += 1)
        {
            float x = 12 + i * 2.8f + (float)_rng.Randf() * 1.2f;
            PlantBush(x, -18.6f + _rng.RandfRange(-0.15f, 0.15f) + Coast(x), _rng.RandfRange(1.3f, 1.8f), 3, 1, true);
        }
        for (int i = 0; i < 26; i += 1)
        {
            float t = (float)(i) / 26;
            PlantBush(-10.1f - (float)_rng.Randf() * 1.4f - t * 3, 8 - t * 24 + _rng.RandfRange(-0.75f, 0.75f), _rng.RandfRange(0.95f, 1.3f), (i is 5 or 9 or 13 ? 5 : ((i % 2 != 0 ? 4 : 6))), 0.22f);
        }
        for (int i = 0; i < 14; i += 1)
        {
            PlantTree(-12.2f - (float)_rng.Randf() * 4, -6 + i * 1.7f + _rng.RandfRange(-1, 1), _rng.RandfRange(1.3f, 1.9f), new int[] { 2, 4, 0, 1 }[i % 4], 0.25f);
        }
        for (int i = 0; i < 10; i += 1)
        {
            PlantTree(-17 - (float)_rng.Randf() * 5, -7 + i * 2.4f + _rng.RandfRange(-1, 1), _rng.RandfRange(1.6f, 2.3f), new int[] { 4, 2, 5, 3 }[i % 4], 0.2f);
        }
        PlantBush(-0.6f, 0.4f, 1.2f, 3, 0.1f);
        foreach (var row in new[] { new float[] { 3, -5.9f, 1.3f }, new float[] { 7.5f, -5.5f, 1.5f }, new float[] { 12.5f, -5.2f, 1.2f }, new float[] { 17, -4.6f, 1.4f } })
        {
            PlantBush(row[0], row[1], row[2], 3, 0.1f);
        }
        for (int i = 0; i < 18; i += 1)
        {
            PlantBush(-0.8f + (float)_rng.Randf() * 1.8f + ((i > 11 ? 2.5f : 0)), -2.5f + i * 0.75f + _rng.RandfRange(-0.6f, 0.6f), _rng.RandfRange(1.15f, 1.65f), 3, 0.3f);
        }
        for (int i = 0; i < 24; i += 1)
        {
            PlantBush(_rng.RandfRange(-1, 11), _rng.RandfRange(4, 13), _rng.RandfRange(1, 1.7f), (i % 3 == 0 ? 3 : i % 2));
        }
    }
    private bool KeepClearing(float x, float z)
    {
        return ((x < -68 && Mathf.Abs(z - 25) < 13 + Mathf.Max(0, -90 - x) * 0.6f) || (x > -68 && x < -56 && z > 37 && z < 48) || (x > -67 && x < -50 && z > 48 && z < 63.5f));
    }
    private void ForestDistribution()
    {
        for (int i = 0; i < 1500; i += 1)
        {
            float x = -76 - Mathf.Pow((float)_rng.Randf(), 0.8f) * 50;
            float z = -40 + (float)_rng.Randf() * 140;
            if (!KeepClearing(x, z))
            {
                PlantTree(x, z, _rng.RandfRange(0.9f, 1.7f), _rng.RandiRange(0, 5));
            }
        }
        for (int i = 0; i < 1800; i += 1)
        {
            float x = _rng.RandfRange(-120, 120);
            float z = 86 + Mathf.Pow((float)_rng.Randf(), 0.8f) * 50;
            bool gap = x > -2 && x < 56 && z < 135;
            if (!(gap && (z < 112 || (float)_rng.Randf() < 0.8f)))
            {
                PlantTree(x, z, (gap ? _rng.RandfRange(0.4f, 0.65f) : _rng.RandfRange(1, 1.9f)), _rng.RandiRange(0, 5));
            }
        }
        for (int i = 0; i < 700; i += 1)
        {
            float x = 100 + Mathf.Pow((float)_rng.Randf(), 0.8f) * 45;
            float z = _rng.RandfRange(-30, 90);
            bool gap = z > -12 && z < 90;
            if (!((gap && x < 110) || (gap && x >= 120 && (float)_rng.Randf() < 0.75f)))
            {
                PlantTree(x, z, (gap ? _rng.RandfRange(0.3f, 0.5f) : _rng.RandfRange(0.9f, 1.7f)), _rng.RandiRange(0, 5));
            }
        }
        for (int i = 0; i < 260; i += 1)
        {
            PlantTree(_rng.RandfRange(30, 66), _rng.RandfRange(79, 89), _rng.RandfRange(0.8f, 1.2f), _rng.RandiRange(0, 5), 0.3f);
        }
        for (int i = 0; i < 50; i += 1)
        {
            PlantTree(_rng.RandfRange(60, 104), _rng.RandfRange(47, 55), _rng.RandfRange(0.35f, 0.5f), _rng.RandiRange(0, 5), 0.3f);
        }
        for (int i = 0; i < 120; i += 1)
        {
            PlantTree(_rng.RandfRange(60, 104), _rng.RandfRange(-14, -8), _rng.RandfRange(1, 1.7f), _rng.RandiRange(0, 5), 0.3f);
        }
        for (int i = 0; i < 200; i += 1)
        {
            float x = _rng.RandfRange(-76, -58);
            float z = _rng.RandfRange(-10, 50);
            if (!KeepClearing(x, z))
            {
                PlantTree(x, z, _rng.RandfRange(1, 1.8f), _rng.RandiRange(0, 5), 0.3f);
            }
        }
        for (int i = 0; i < 900; i += 1)
        {
            float x = _rng.RandfRange(-75, 75);
            float z = _rng.RandfRange(-4, 88);
            float shrine_distance = new Vector2(x, z - 30).Length();
            if ((shrine_distance < 23 || (z > 4 && z < 26 && x > -16 && x < 12) || (z > 70 && x > 6 && x < 50) || KeepClearing(x, z)))
            {
                continue;
            }
            if ((float)_rng.Randf() < ((shrine_distance < 27 ? 0.35f : 0.55f)) || (z > 56 && z < 79 && x > 44 && x < 80))
            {
                continue;
            }
            PlantTree(x, z, (z > 42 && z < 57 && x > 56 ? _rng.RandfRange(0.35f, 0.5f) : _rng.RandfRange(0.8f, 1.6f)), _rng.RandiRange(0, 5));
        }
        for (int i = 0; i < 400; i += 1)
        {
            float x = _rng.RandfRange(-75, 75);
            float z = _rng.RandfRange(-4, 88);
            if ((KeepClearing(x, z) || (z > 4 && z < 26 && x > -16 && x < 12) || (z > 70 && x > 6 && x < 50) || (z > 56 && z < 78 && x > 34 && x < 66)))
            {
                continue;
            }
            PlantBush(x, z, _rng.RandfRange(0.9f, 1.9f), _rng.RandiRange(0, 2));
        }
        for (int i = 0; i < 40; i += 1)
        {
            PlantTree(_rng.RandfRange(-75, -37), _rng.RandfRange(-21.5f, -18.5f), _rng.RandfRange(0.8f, 1.4f), _rng.RandiRange(0, 5));
        }
    }
    private async Task GrassFields()
    {
        _rng.Seed = 4242;
        var mesh = _plants.GrassMesh();
        var material = new ShaderMaterial();
        material.Shader = GD.Load<Shader>("res://shaders/grass.gdshader");
        var transforms = new List<Transform3D>();
        var samples = new Dictionary<Vector2I, Vector2>();
        int attempts = 0;
        // Grow up to 380,000 clumps. Spatial batches let Godot cull
        // fields behind the camera and beyond the atmospheric distance.
        while (transforms.Count < 380000 && attempts < 1140000)
        {
            attempts += 1;
            if (attempts % 10000 == 0)
            {
                await NextFrame();
            }
            float x = _rng.RandfRange(-125, 125);
            float z = _rng.RandfRange(-30, 100);
            var cell = new Vector2I(Mathf.FloorToInt(x * 2), Mathf.FloorToInt(z * 2));
            if (!samples.ContainsKey(cell))
            {
                float sx = cell.X * 0.5f + 0.25f;
                float sz = cell.Y * 0.5f + 0.25f;
                samples[cell] = new Vector2((_world.Excluded(sx, sz, 0.6f) ? -1 : 1), _world.HeightAt(sx, sz));
            }
            Vector2 sample = samples[cell];
            if (sample.X < 0 || z - Coast(x) < -27)
            {
                continue;
            }
            if (x > -9 && x < -3.8f && z - Coast(x) > -8.5f && z - Coast(x) < 7)
            {
                continue;
            }
            float distance = new Vector2(x, z).Length();
            float density = (z > 90 || x < -80 || x > 105 ? 0.25f : ((distance < 25 ? 1.0f : 0.6f)));
            if ((float)_rng.Randf() > density || sample.Y < -1.5f)
            {
                continue;
            }
            float patch = 0.5f + 0.25f * Mathf.Sin(x * 0.12f + 40) * Mathf.Cos(z * 0.12f + 9) + 0.15f * Mathf.Sin(x * 0.27f + z * 0.18f);
            if (patch < 0.36f && (float)_rng.Randf() < 0.6f)
            {
                continue;
            }
            float size = Mathf.Min(1.05f, 0.45f + patch * 0.7f + (float)_rng.Randf() * 0.3f);
            if (z < -4 && z - Coast(x) < -16.5f)
            {
                size *= 0.35f;
            }
            if (x < -9 && x > -11.6f && z - Coast(x) > -8.5f && z < 8)
            {
                size *= 0.3f;
            }
            if (x > -3.8f && x < -.5f && z > -9 && z < 8)
            {
                size *= Mathf.Lerp(.35f, .8f, Mathf.SmoothStep(-3.8f, -.5f, x));
            }
            size *= (0.9f + (1 - Mathf.Min(1, distance / 40)) * 0.3f) * ((density < 1 ? 1.35f : 1));
            float ground = (distance < 25 ? _world.HeightAt(x, z) : sample.Y);
            transforms.Add(new Transform3D(new Basis(Vector3.Up, (float)_rng.Randf() * Mathf.Tau).Scaled(new Vector3(size * _rng.RandfRange(0.8f, 1.2f), size, size * _rng.RandfRange(0.8f, 1.2f))), new Vector3(x, ground - 0.02f, z)));
        }
        for (int i = 0; i < 250; i += 1)
        {
            bool seaside = (float)_rng.Randf() < 0.3f;
            float x = (seaside ? _rng.RandfRange(-2.6f, -1.8f) : _rng.RandfRange(-3.7f, -2.4f));
            float z = (seaside ? _rng.RandfRange(-8, -3.6f) : _rng.RandfRange(-3.6f, 1.4f));
            float size = (seaside ? _rng.RandfRange(0.9f, 1.3f) : _rng.RandfRange(1, 1.4f));
            size *= Mathf.Lerp(.36f, .72f, Mathf.SmoothStep(-3.7f, -1.8f, x));
            transforms.Add(new Transform3D(new Basis(Vector3.Up, (float)_rng.Randf() * Mathf.Tau).Scaled(Vector3.One * size), new Vector3(x, _world.HeightAt(x, z) - 0.02f, z)));
        }
        Batch(mesh, material, transforms, "Wind grass", 88);
    }
    private void Rosettes(IReadOnlyList<float[]>? rows = null, Color? plant_color = null, Color second_color = default)
    {
        plant_color ??= new Color("2f6a36");
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        CozyLeafPainter.Paint(image, new Vector2(128, 130), 216, 184, 0, 0.71f, CozyLeafPainter.Profile.Rounded, true);
        for (int y = 35; y < 239; y += 1)
        {
            for (int x = 125; x < 131; x += 1)
            {
                image.SetPixel(x, y, new Color(0.87f, 0.87f, 0.87f, 1));
            }
        }
        for (int level = 0; level < 5; level += 1)
        {
            foreach (var side in new int[] { -1, 1 })
            {
                for (int step = 0; step < 67; step += 1)
                {
                    int x = 128 + step * side;
                    int y = 213 - level * 34 - step / 2;
                    for (int thickness = -1; thickness < 2; thickness += 1)
                    {
                        if (image.GetPixel(x, y + thickness).A > 0.5f)
                        {
                            image.SetPixel(x, y + thickness, new Color(0.87f, 0.87f, 0.87f, 1));
                        }
                    }
                }
            }
        }
        image.GenerateMipmaps();
        _large_leaf_texture = ImageTexture.CreateFromImage(image);
        var material = FoliageMaterial(_large_leaf_texture, plant_color.Value, 0.05f);
        material.SetShaderParameter("near_fade", 0.9f);
        material.SetShaderParameter("gradient_bottom", new Vector3(0.85f, 0.95f, 1.0f));
        material.SetShaderParameter("gradient_top", new Vector3(1.1f, 1.05f, 0.8f));
        if (second_color.A > 0)
        {
            Color base_linear = plant_color.Value.SrgbToLinear();
            Color tip_linear = second_color.SrgbToLinear();
            material.SetShaderParameter("gradient_top", new Vector3(Mathf.Min(4, tip_linear.R / Mathf.Max(base_linear.R, 0.001f)), Mathf.Min(4, tip_linear.G / Mathf.Max(base_linear.G, 0.001f)), Mathf.Min(4, tip_linear.B / Mathf.Max(base_linear.B, 0.001f))));
        }
        if (rows == null || rows.Count == 0)
        {
            rows = new[] { new float[] { -4.3f, -3.4f, 1.5f, 3 }, new float[] { -4.9f, -2.6f, 1.3f, 5 }, new float[] { -3.7f, -4.3f, 1.45f, 7 }, new float[] { -3.2f, -5.4f, 1.3f, 11 }, new float[] { -4, -2.3f, 1.1f, 13 }, new float[] { -4.6f, -4.4f, 1.2f, 17 }, new float[] { -3, -3, 1.4f, 19 } };
        }
        foreach (var row in rows)
        {
            _rng.Seed = (uint)row[3];
            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            int count = _rng.RandiRange(7, 11);
            for (int i = 0; i < count; i += 1)
            {
                float angle = (float)(i) / count * Mathf.Tau + (float)_rng.Randf() * 0.6f;
                float lean = _rng.RandfRange(0.5f, 1.2f);
                float size = _rng.RandfRange(0.7f, 1.2f) * row[2] * .72f;
                var basis = new Basis(Vector3.Up, -angle) * new Basis(Vector3.Right, -lean);
                for (int segment = 0; segment < 2; segment += 1)
                {
                    foreach (var k in new int[] { 0, 2, 1, 1, 2, 3 })
                    {
                        float v = (float)(segment + k / 2) / 2;
                        float u = k % 2;
                        st.SetUV(new Vector2(u, 1 - v));
                        st.SetColor(new Color(1, 1, 1, v * 0.9f));
                        st.SetNormal((basis * new Vector3(0, 0.5f, 1)).Normalized());
                        st.AddVertex(((basis * new Vector3((u - 0.5f) * size, v * size * 1.15f, size * 0.09f * Mathf.Sin(v * Mathf.Pi))) + new Vector3(Mathf.Cos(angle) * 0.15f, 0.1f, -Mathf.Sin(angle) * 0.15f)));
                    }
                }
            }
            var instance = new MeshInstance3D();
            instance.Name = "Broad dock leaves";
            instance.Mesh = st.Commit();
            instance.MaterialOverride = material;
            float lift = (row.Length > 4 ? row[4] : 0);
            int tiers = row.Length > 5 ? (int)row[5] : 1;
            instance.Position = new Vector3(row[0], _world.HeightAt(row[0], row[1]) - 0.05f + lift, row[1]);
            AddChild(instance);
            for (int tier = 1; tier < tiers; tier += 1)
            {
                var lower = (MeshInstance3D)instance.Duplicate();
                lower.Scale = Vector3.One * Mathf.Pow(0.82f, tier);
                lower.Position = new Vector3(lower.Position.X, lower.Position.Y - lift * (float)(tier) / tiers, lower.Position.Z);
                AddChild(lower);
            }
            if (lift > 0.1f)
            {
                CozyPrimitives.Cylinder(this, new Vector3(row[0], _world.HeightAt(row[0], row[1]) + lift * 0.5f, row[1]), 0.05f, 0.03f, lift, _world.Palette.Color("3a5936"));
            }
        }
    }
    private void Flowers()
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        foreach (var angle in new float[] { 0, Mathf.Pi * 0.5f })
        {
            var basis = new Basis(Vector3.Up, angle);
            foreach (var k in new int[] { 0, 2, 1, 0, 3, 2 })
            {
                Vector2 uv = new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) }[k];
                st.SetUV(uv);
                st.SetNormal(Vector3.Up);
                st.SetColor(new Color(1, 1, 1, 1 - uv.Y));
                st.AddVertex(basis * new Vector3((uv.X - 0.5f) * 0.6f, (1 - uv.Y) * 0.7f, 0));
            }
        }
        var mesh = st.Commit();
        var sets = new[] { new FlowerSet { Color = new Color("d6566e"), Patches = new[] { new float[] { -3.3f, -4.6f, 0.7f, 30 }, new float[] { -3.2f, -6.3f, 0.7f, 25 }, new float[] { -3.5f, -7.75f, 0.6f, 24 }, new float[] { -1.4f, -7.3f, 0.7f, 26 }, new float[] { 1.8f, -7.15f, 0.8f, 30 }, new float[] { 5.4f, -6.95f, 0.7f, 22 } } }, new FlowerSet { Color = new Color("de7288"), Patches = new[] { new float[] { -3.3f, -3.9f, 0.5f, 10 }, new float[] { -2.6f, -7.95f, 0.45f, 9 }, new float[] { 0.2f, -7.4f, 0.5f, 10 }, new float[] { 3.7f, -7.2f, 0.5f, 9 } } }, new FlowerSet { Color = new Color("ee7a2a"), Patches = new[] { new float[] { -9.9f, 1.5f, 0.7f, 30 }, new float[] { -9.9f, -2.5f, 0.7f, 30 }, new float[] { -9.9f, -6, 0.7f, 25 } } }, new FlowerSet { Color = new Color("f2cf4a"), Patches = new[] { new float[] { -9.9f, 4.5f, 0.7f, 20 }, new float[] { -9.9f, -4.2f, 0.6f, 15 } } }, new FlowerSet { Color = new Color("f6f2e8"), Patches = new[] { new float[] { 20, -18, 3, 60 }, new float[] { -25, -18.5f, 3, 50 } } } };
        for (int i = 0; i < sets.Length; i += 1)
        {
            var transforms = new List<Transform3D>();
            foreach (var patch in sets[i].Patches)
            {
                for (int j = 0; j < patch[3]; j += 1)
                {
                    float angle = (float)_rng.Randf() * Mathf.Tau;
                    float radius = Mathf.Sqrt((float)_rng.Randf()) * patch[2];
                    float x = patch[0] + Mathf.Cos(angle) * radius;
                    float z = patch[1] + Mathf.Sin(angle) * radius;
                    float size = (i < 2 ? _rng.RandfRange(0.8f, 1.3f) : _rng.RandfRange(0.9f, 1.6f));
                    transforms.Add(new Transform3D(new Basis(Vector3.Up, (float)_rng.Randf() * Mathf.Tau).Scaled(Vector3.One * size), new Vector3(x, _world.HeightAt(x, z) - 0.02f, z)));
                }
            }
            var material = FoliageMaterial(SeabreezeTextures.FlowerTexture(sets[i].Color, 9 + i), Colors.White, 0.16f);
            material.SetShaderParameter("color_texture", true);
            material.SetShaderParameter("near_fade", 0.3f);
            Batch(mesh, material, transforms, "Wildflower patches", 90);
        }
    }
    private void BroadTree(float x, float z, float height, float radius, int seed_value, TreeOptions? options = null)
    {
        options ??= new();
        _rng.Seed = (uint)seed_value;
        var canopy_material = FoliageMaterial(_leaf_textures[0], new Color(unchecked((uint)(((int)(options.Color) << 8) | 255))), 0.14f);
        canopy_material.SetShaderParameter("band_lift", options.LeafLift);
        var trunk = new SurfaceTool();
        trunk.Begin(Mesh.PrimitiveType.Triangles);
        var ends = new List<Vector3>();
        for (int i = 0; i < 4; i += 1)
        {
            ends.Add(new Vector3(_rng.RandfRange(-0.65f, 0.65f) * radius, height + radius * (.42f + (float)_rng.Randf() * .4f), _rng.RandfRange(-0.65f, 0.65f) * radius));
        }
        float trunkRadius = Mathf.Min(.42f, .08f + height * .035f);
        float forkHeight = height * .78f + Mathf.Min(.35f, radius * .15f);
        var bend = new Vector3(Mathf.Sin(seed_value), 0, Mathf.Cos(seed_value * 1.7f)) * trunkRadius;
        var fork = new Vector3(0, forkHeight, 0) + bend;
        _plants.TaperedBranch(trunk, new Vector3(0, -.08f, 0), fork * .2f, trunkRadius * 1.45f, trunkRadius, 12);
        _plants.TaperedBranch(trunk, fork * .2f, fork, trunkRadius, trunkRadius * .62f, 12);
        foreach (var end in ends)
        {
            var elbow = fork.Lerp(end, .55f) + Vector3.Up * radius * .08f;
            _plants.TaperedBranch(trunk, fork, elbow, trunkRadius * .6f, trunkRadius * .32f, 9);
            _plants.TaperedBranch(trunk, elbow, end, trunkRadius * .32f, trunkRadius * .07f, 8);
        }
        trunk.GenerateNormals();
        var stem = new MeshInstance3D();
        stem.Mesh = trunk.Commit();
        stem.MaterialOverride = SeabreezeTextures.BarkMaterial();
        ((StandardMaterial3D)stem.MaterialOverride).AlbedoColor = new Color(unchecked((uint)(((int)(options.Bark) << 8) | 255)));
        stem.Position = new Vector3(x, _world.HeightAt(x, z) - 0.2f, z);
        AddChild(stem);
        var crown = new MeshInstance3D();
        crown.Name = $"Area broadleaf {x} {z}";
        crown.Mesh = _plants.Canopy(new Vector3(0, height + radius * 0.55f, 0), new Vector3(radius, radius * 0.72f, radius), 8, options.Clusters, 7, options.CardSize, options.ClusterRadius, height * 0.5f, height + radius * 1.6f);
        crown.MaterialOverride = canopy_material;
        crown.Position = stem.Position;
        if (!options.Shadow)
        {
            crown.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        }
        AddChild(crown);
    }
    private void PineTree(float x, float z, float height, int seed_value)
    {
        _rng.Seed = (uint)seed_value;
        float ground = _world.HeightAt(x, z) - 0.2f;
        float lean = _rng.RandfRange(-0.125f, 0.125f);
        MeshInstance3D trunk = CozyPrimitives.Cylinder(this, new Vector3(x - Mathf.Sin(lean) * height * 0.5f, ground + height * 0.5f, z), 0.42f, 0.16f, height, _world.Palette.Color("8f6a58"));
        trunk.Rotation = new Vector3(trunk.Rotation.X, trunk.Rotation.Y, lean);
        int count = 3 + (((float)_rng.Randf() < 0.5f ? 1 : 0));
        float phase = (float)_rng.Randf() * Mathf.Tau;
        for (int i = 0; i < count; i += 1)
        {
            float fraction = (float)(i) / (count - 1);
            float h = height * (0.5f + fraction * 0.5f);
            float spread = height * 0.12f * (1 - fraction);
            float angle = phase + i * 2.2f + _rng.RandfRange(-0.4f, 0.4f);
            var center = new Vector3(Mathf.Cos(angle) * spread - Mathf.Sin(lean) * h, h, Mathf.Sin(angle) * spread);
            float radius = 0.34f * height * (1 - 0.5f * fraction) + (float)_rng.Randf() * 0.5f;
            var mesh = _plants.PineTier(center, radius, height);
            var crown = new MeshInstance3D();
            crown.Name = "Japanese pine tiers";
            crown.Mesh = mesh;
            crown.MaterialOverride = FoliageMaterial(_pine_texture, new Color("35603a"), 0.06f);
            ((ShaderMaterial)crown.MaterialOverride).SetShaderParameter("band_lift", 0.08f);
            crown.Position = new Vector3(x, ground, z);
            AddChild(crown);
            CozyPrimitives.Beam(this, new Vector3(x - Mathf.Sin(lean) * h * 0.8f, ground + h * 0.8f, z), new Vector3(x, ground, z) + center, 0.11f, _world.Palette.Color("8f6a58"));
            foreach (var branch in new float[] { -1, 1 })
            {
                float branch_angle = angle + branch * 1.9f + _rng.RandfRange(-0.4f, 0.4f);
                CozyPrimitives.Beam(this, new Vector3(x, ground, z) + center, (new Vector3(x, ground, z) + center + new Vector3(Mathf.Cos(branch_angle) * radius * 0.7f, 0.15f, Mathf.Sin(branch_angle) * radius * 0.7f)), 0.065f, _world.Palette.Color("8f6a58"));
            }
        }
    }
    private void Meadow(Rect2 rect, float density, float height, bool shrine = false, MeadowOptions? options = null)
    {
        options ??= new();
        _rng.Seed = unchecked((uint)(Mathf.FloorToInt(rect.Position.X * 3 + rect.End.Y * 5) + 7));
        var mesh = _plants.GrassMesh();
        var transforms = new List<Transform3D>();
        int amount = (int)(rect.Size.X * rect.Size.Y * density);
        for (int i = 0; i < amount; i += 1)
        {
            float x = _rng.RandfRange(rect.Position.X, rect.End.X);
            float z = _rng.RandfRange(rect.Position.Y, rect.End.Y);
            if (!options.Force && (_world.SurfaceAt(x, z) != "grass" && _world.SurfaceAt(x, z) != "hardpack"))
            {
                continue;
            }
            if (shrine && (ShrinePlantSkip(x, z) || Mathf.Abs(x - ShrinePath(z)) < 0.45f))
            {
                continue;
            }
            if (!shrine && _world.RoadInfo(x, z).D < 4.5f)
            {
                continue;
            }
            float yaw = (float)_rng.Randf() * Mathf.Tau;
            bool seed_head = (float)_rng.Randf() < ((shrine ? 0.26f : options.SeedHeads));
            float scale_value = height * _rng.RandfRange(0.75f, 1.25f) * ((seed_head ? 1.45f : 1));
            if (shrine)
            {
                scale_value *= 1 - 0.65f * Mathf.Clamp((z - 16.5f) / 2, 0, 1);
            }
            float width = scale_value * ((seed_head ? 0.55f : 1.2f * options.Width));
            transforms.Add(new Transform3D(new Basis(Vector3.Up, yaw).Scaled(new Vector3(width, scale_value, width)), new Vector3(x, _world.HeightAt(x, z) - 0.02f, z)));
        }
        var material = new ShaderMaterial();
        material.Shader = GD.Load<Shader>("res://shaders/grass.gdshader");
        material.SetShaderParameter("grass_base", options.Base ?? ((shrine ? new Vector3(0.12f, 0.27f, 0.22f) : new Vector3(0.2f, 0.32f, 0.12f))));
        material.SetShaderParameter("grass_mid", options.Mid ?? ((shrine ? new Vector3(0.27f, 0.43f, 0.19f) : new Vector3(0.42f, 0.55f, 0.2f))));
        material.SetShaderParameter("grass_tip", options.Tip ?? ((shrine ? new Vector3(0.43f, 0.55f, 0.24f) : new Vector3(0.72f, 0.76f, 0.3f))));
        material.SetShaderParameter("band_lift", 0.05f);
        Batch(mesh, material, transforms, "Area meadow", 90);
    }
    private float ShrinePath(float z)
    {
        var points = new[] { new Vector2(-3.2f, 21.5f), new Vector2(-5.5f, 20.5f), new Vector2(-7.5f, 18.5f), new Vector2(-9, 15), new Vector2(-9.5f, 12), new Vector2(-9, 9), new Vector2(-8.5f, 6) };
        for (int i = 1; i < points.Length; i += 1)
        {
            if (z <= points[i - 1].Y && z >= points[i].Y)
            {
                return Mathf.Lerp(points[i - 1].X, points[i].X, (points[i - 1].Y - z) / (points[i - 1].Y - points[i].Y));
            }
        }
        return 99;
    }
    private bool ShrinePlantSkip(float x, float z)
    {
        return new Vector2(x + 4.3f, z - 14.5f).Length() < 2 || (Mathf.Abs(x - 0.5f) < 4.6f && z > 19.6f);
    }
    private void ShrineFlowers(Vector2 center, float radius, int count, Color color, int seed_value, float scale_value = 1)
    {
        if (center != _flower_patch_center)
        {
            _rng.Seed = unchecked((uint)(Mathf.FloorToInt(center.X * 11 + center.Y * 3) + 55));
            _flower_patch_center = center;
        }
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        foreach (var angle in new float[] { 0, Mathf.Pi * 0.5f })
        {
            var basis = new Basis(Vector3.Up, angle);
            for (int segment = 0; segment < 4; segment += 1)
            {
                foreach (var k in new int[] { 0, 2, 1, 1, 2, 3 })
                {
                    float v = (float)(segment + k / 2) / 4;
                    float u = k % 2;
                    st.SetUV(new Vector2(u, 1 - v));
                    st.SetNormal(Vector3.Up);
                    st.SetColor(new Color(1, 1, 1, v));
                    st.AddVertex(basis * new Vector3((u - 0.5f) * 0.5f, v * 1.4f, 0));
                }
            }
        }
        var mesh = st.Commit();
        var transforms = new List<Transform3D>();
        for (int i = 0; i < count; i += 1)
        {
            float angle = (float)_rng.Randf() * Mathf.Tau;
            float distance = Mathf.Sqrt((float)_rng.Randf()) * radius;
            Vector2 p = center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * distance;
            if (ShrinePlantSkip(p.X, p.Y) || Mathf.Abs(p.X - ShrinePath(p.Y)) < 0.9f)
            {
                continue;
            }
            float size = scale_value * _rng.RandfRange(0.75f, 1.25f) * (1 - 0.65f * Mathf.Clamp((p.Y - 16.5f) / 2, 0, 1));
            var pos = new Vector3(p.X, _world.HeightAt(p.X, p.Y) - 0.02f - (float)_rng.Randf() * 0.3f * size, p.Y);
            float rotation = (float)_rng.Randf() * Mathf.Pi;
            transforms.Add(new Transform3D(new Basis(Vector3.Up, rotation).Scaled(new Vector3(size * _rng.RandfRange(0.85f, 1.15f), size, size * _rng.RandfRange(0.85f, 1.15f))), pos));
        }
        string kind = (color.B > color.R ? "aster" : ((color.G < 0.5f ? "red" : "buttercup")));
        var material = FoliageMaterial(SeabreezeTextures.ShrineFlowerTexture(kind, seed_value), Colors.White, 0.2f);
        material.SetShaderParameter("color_texture", true);
        material.SetShaderParameter("band_lift", 0.3f);
        material.SetShaderParameter("band_scale", 0.45f);
        material.SetShaderParameter("near_fade", 0.4f);
        Batch(mesh, material, transforms, "Shrine wildflowers", 90);
    }
    private void GiantShrineTree()
    {
        _rng.Seed = 5;
        var position = new Vector3(-4.3f, _world.HeightAt(-4.3f, 14.5f) - 0.3f, 14.5f);
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        var rootFaces = new List<Vector3>();
        for (int level = 0; level < 20; level += 1)
        {
            for (int segment = 0; segment < 32; segment += 1)
            {
                foreach (var k in new int[] { 0, 2, 1, 1, 2, 3 })
                {
                    float t = (float)(level + k / 2) / 20;
                    float angle = (float)(segment + k % 2) / 32 * Mathf.Tau;
                    float radius = (1.15f * (1 - 0.38f * t) * (1 + 0.2f * Mathf.Sin(angle * 5 + t * 9) * (1 - t * 0.5f) + 0.12f * Mathf.Sin(angle * 2 - t * 4) + 0.07f * Mathf.Sin(angle * 9 + t * 21) + ((0.85f * Mathf.Pow(Mathf.Max(0, Mathf.Cos(angle * 4 + 0.6f)), 2.5f) + 0.22f) * Mathf.Pow(Mathf.Max(0, 1 - t * 3.3f), 2))));
                    float hollow_distance = (new Vector2(Mathf.Abs(Mathf.Wrap(angle + 1.065f, -Mathf.Pi, Mathf.Pi)) / (0.55f * 1.6f), (t * 12 - 2.7f) / (1.05f * 1.6f)).Length());
                    radius -= 0.36f * (1 - Mathf.SmoothStep(0.3f, 1.0f, hollow_distance)) * 1.15f * (1 - 0.38f * t);
                    st.SetUV(new Vector2((float)(segment + k % 2) / 32, t));
                    var vertex = new Vector3(Mathf.Cos(angle) * radius + Mathf.Sin(t * 4.5f + 0.4f) * 0.3f + Mathf.Sin(t * 11) * 0.1f, t * 12, Mathf.Sin(angle) * radius + Mathf.Cos(t * 3.2f) * 0.26f + Mathf.Sin(t * 8.5f + 1) * 0.08f);
                    // Ground the existing continuous trunk flare. A second collar
                    // would intersect this irregular surface and create a visible seam.
                    float soil = _world.HeightAt(position.X + vertex.X, position.Z + vertex.Z) - position.Y - .12f;
                    vertex.Y += soil * Mathf.Pow(Mathf.Max(0, 1 - vertex.Y / 2.4f), 2);
                    st.AddVertex(vertex);
                    if (level < 4) rootFaces.Add(vertex);
                }
            }
        }
        st.GenerateNormals();
        var bark = SeabreezeTextures.GiantBarkMaterial(position);
        var trunk = new MeshInstance3D();
        trunk.Name = "Ancient shrine tree";
        trunk.Mesh = st.Commit();
        trunk.MaterialOverride = bark;
        trunk.Position = position;
        AddChild(trunk);
        var rootSurface = new SurfaceTool();
        rootSurface.Begin(Mesh.PrimitiveType.Triangles);
        // The authored trunk uses inward render winding; physics needs outward
        // faces. Reuse its exact basal vertices without a second visible surface.
        for (int i = 0; i < rootFaces.Count; i += 3)
        {
            rootSurface.AddVertex(rootFaces[i]);
            rootSurface.AddVertex(rootFaces[i + 2]);
            rootSurface.AddVertex(rootFaces[i + 1]);
        }
        var rootBody = new StaticBody3D { Position = position };
        AddChild(rootBody);
        CozyCollision.Mesh(rootBody, rootSurface.Commit());
        for (int i = 0; i < 7; i += 1)
        {
            float angle = (float)(i) / 7 * Mathf.Tau;
            CozyPrimitives.Beam(this, position + new Vector3(0, 10.5f, 0), position + new Vector3(Mathf.Cos(angle) * 4.5f, 13 + (float)_rng.Randf() * 3, Mathf.Sin(angle) * 4.5f), 0.32f, bark);
        }
        var crown = new MeshInstance3D();
        crown.Mesh = _plants.Canopy(new Vector3(0, 14.5f, 0), new Vector3(7, 4.2f, 7), 9, 150, 7, 2.1f, 1.5f, 6, 20);
        crown.MaterialOverride = FoliageMaterial(_leaf_textures[0], new Color("4a7c40"), 0.08f);
        ((ShaderMaterial)crown.MaterialOverride).SetShaderParameter("band_lift", 0.34f);
        crown.Position = position;
        crown.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        AddChild(crown);
        var ivy = new SurfaceTool();
        ivy.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < 340; i += 1)
        {
            float angle = -1.065f + ((i % 2 != 0 ? 0.85f : -0.85f)) + _rng.RandfRange(-0.25f, 0.25f);
            float h = 0.8f + Mathf.Pow((float)_rng.Randf(), 0.9f) * 7.5f;
            float radius = 1.15f * (1 - 0.38f * h / 12) * 1.18f + 0.05f + (float)_rng.Randf() * 0.3f;
            float size = _rng.RandfRange(0.22f, 0.30f) * 1.8f;
            var center = new Vector3(Mathf.Cos(angle) * radius, h, Mathf.Sin(angle) * radius);
            var basis = new Basis(Vector3.Up, Mathf.Pi * 0.5f - angle) * new Basis(Vector3.Forward, _rng.RandfRange(-1.2f, 1.2f));
            foreach (var k in new int[] { 0, 2, 1, 0, 3, 2 })
            {
                Vector2 uv = new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) }[k];
                ivy.SetUV(uv);
                ivy.SetNormal((basis * Vector3.Forward).Normalized());
                ivy.SetColor(new Color(1, 1, 1, 0.15f));
                ivy.AddVertex(center + basis * new Vector3((uv.X - 0.5f) * size, (0.5f - uv.Y) * size * 1.15f, 0));
            }
        }
        var ivy_node = new MeshInstance3D();
        ivy_node.Name = "Climbing ivy";
        ivy_node.Mesh = ivy.Commit();
        ivy_node.MaterialOverride = FoliageMaterial(_large_leaf_texture, new Color("4d8a3f"), 0.04f);
        ((ShaderMaterial)ivy_node.MaterialOverride).SetShaderParameter("gradient_bottom", new Vector3(0.62f, 0.72f, 0.85f));
        ((ShaderMaterial)ivy_node.MaterialOverride).SetShaderParameter("gradient_top", new Vector3(1, 1, 0.85f));
        ivy_node.Position = position;
        AddChild(ivy_node);
        var body = new StaticBody3D();
        var shape = new CollisionShape3D();
        var cylinder = new CylinderShape3D();
        cylinder.Radius = 1.6f;
        cylinder.Height = 3;
        shape.Shape = cylinder;
        shape.Position = new Vector3(shape.Position.X, 1.5f, shape.Position.Z);
        body.Position = position;
        body.AddChild(shape);
        AddChild(body);
    }
    private void AreaFlora()
    {
        // Shrine's authored flora is separate from the background distribution.
        GiantShrineTree();
        BroadTree(10.5f, 24.5f, 9.5f, 4.4f, 61, new TreeOptions { Color = (int)(4025912), LeafLift = 0.12f });
        BroadTree(-14.5f, 25.5f, 4, 4.5f, 67);
        foreach (var row in new[] { new float[] { 13.5f, 30, 12, 62 }, new float[] { 8, 39, 11, 63 }, new float[] { -12, 38, 9, 64 }, new float[] { -12.5f, 26, 9, 66 }, new float[] { -4.5f, 37.5f, 7, 65 }, new float[] { -5.2f, 28.5f, 6.5f, 68 } })
        {
            PineTree(row[0], row[1], row[2], (int)(row[3]));
        }
        ShrineFlowers(new Vector2(-0.5f, 15), 8.5f, 288, new Color("a696ca"), 300);
        ShrineFlowers(new Vector2(-0.5f, 15), 8.5f, 192, new Color("eeae36"), 301);
        ShrineFlowers(new Vector2(5, 12), 4, 24, new Color("dd4b56"), 302, 0.8f);
        ShrineFlowers(new Vector2(5, 12), 4, 56, new Color("eeae36"), 303, 0.8f);
        Meadow(new Rect2(-12, 6, 24, 13.5f), 7.5f, 1, true);
        Rosettes(new[] { new float[] { -7.5f, 15, 2, 3 }, new float[] { -3, 14.8f, 1.6f, 5 }, new float[] { -9.5f, 16, 1.6f, 7 }, new float[] { -1, 13.5f, 1.4f, 9 }, new float[] { 6.5f, 14.5f, 1.7f, 11 }, new float[] { 3.5f, 13.5f, 1.2f, 13 }, new float[] { -11, 9, 1.4f, 15 } });
        // Village trees form the massive green roof over the lane and hide the railway.
        foreach (var row in new[] { new float[] { -5, 89, 10, 6.5f, 41 }, new float[] { -43, 90, 9, 5.5f, 42 }, new float[] { 14, 88, 9, 5.5f, 43 }, new float[] { -7, 62.8f, 12, 10, 44 }, new float[] { -20, 63.8f, 13, 12, 47 }, new float[] { -5.6f, 81.3f, 13, 9.5f, 46 }, new float[] { -31, 73.6f, 4.5f, 8, 48 }, new float[] { -38.5f, 71, 4.5f, 8, 50 }, new float[] { -34.5f, 68.8f, 4.5f, 7, 51 }, new float[] { -30, 61.5f, 8, 9, 49 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Clusters = (int)((row[2] == 4.5f ? 220 : 110)) });
        }
        // Paddy approach uses unusually small leaf cards (0.4m rather than 1.6m).
        BroadTree(58.8f, -3.6f, 4.4f, 2.9f, 12, new TreeOptions { CardSize = 0.4f, Clusters = (int)(650), ClusterRadius = 0.6f, LeafLift = 0.34f, Color = (int)(5672000) });
        BroadTree(61.6f, -3, 1.2f, 1.9f, 14, new TreeOptions { CardSize = 0.42f, Clusters = (int)(360), ClusterRadius = 0.55f, LeafLift = 0.3f });
        BroadTree(49, 35, 8, 5, 12);
        foreach (var row in new[] { new float[] { 47, -3, 10, 13 }, new float[] { 101.5f, 12, 9.5f, 19 }, new float[] { 104, 16, 7.5f, 20 } })
        {
            PineTree(row[0], row[1], row[2], (int)(row[3]));
        }
        foreach (var row in new[] { new float[] { 76, 61, 5.5f, 4.5f, 40 }, new float[] { 81, 62, 6, 4.5f, 41 }, new float[] { 86, 61.5f, 6.5f, 5, 42 }, new float[] { 91, 63, 6, 4.5f, 43 }, new float[] { 96, 62, 6.5f, 5, 44 }, new float[] { 101, 62.5f, 6, 4.5f, 45 }, new float[] { 106, 64, 6, 4.5f, 46 }, new float[] { 111, 65, 5.5f, 4.5f, 47 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)(4091450) });
        }
        FarmFlora();
        RailFlora();
        VendingFlora();
    }
    private void FarmFlora()
    {
        BroadTree(57.6f, 66.8f, 0.4f, 1.8f, 41, new TreeOptions { Color = (int)(4160066), LeafLift = 0.4f, CardSize = 0.9f, Clusters = (int)(100), ClusterRadius = 0.8f, Shadow = false });
        BroadTree(59.5f, 67.2f, 9, 4.5f, 42, new TreeOptions { Color = (int)(3499578), LeafLift = 0.3f, CardSize = 1.3f, Shadow = false });
        BroadTree(47.4f, 63.2f, 6, 4.6f, 43, new TreeOptions { Color = (int)(3499578), LeafLift = 0.3f, CardSize = 1.3f, Shadow = false });
        foreach (var row in new[] { new float[] { 58, 77.5f, 1.5f, 2.5f, 71 }, new float[] { 54, 78, 1.5f, 2.5f, 72 }, new float[] { 40, 83, 7, 5, 65 }, new float[] { 46, 83, 4.5f, 4.5f, 61 }, new float[] { 54, 83.5f, 4.5f, 4.5f, 62 }, new float[] { 58, 84, 4.5f, 4.5f, 66 }, new float[] { 62, 83, 4.5f, 4.5f, 63 }, new float[] { 70, 82, 7, 5, 64 }, new float[] { 43, 86, 6.5f, 4.5f, 21 }, new float[] { 52, 86.5f, 5, 4.5f, 22 }, new float[] { 60, 85, 5, 4.5f, 24 }, new float[] { 34, 86, 7, 4.5f, 23 }, new float[] { 36, 84, 10, 6, 81 }, new float[] { 41, 86.5f, 11, 6, 82 }, new float[] { 30, 82, 9, 5.5f, 83 }, new float[] { 24, 78, 6.5f, 4.5f, 25 }, new float[] { 69, 84, 6.5f, 5.5f, 28 }, new float[] { 67.5f, 82.5f, 4.5f, 5, 31 }, new float[] { 72.5f, 85.5f, 6, 5, 32 }, new float[] { 75.5f, 87, 7, 5.5f, 29 }, new float[] { 81, 89, 7, 5.5f, 30 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)((row[2] == 1.5f ? 8368718 : 3038260)) });
        }
        foreach (var row in new[] { new float[] { 44, 81, 51 }, new float[] { 50, 81.5f, 52 }, new float[] { 56, 81, 53 }, new float[] { 62, 81.5f, 54 }, new float[] { 68, 81, 55 }, new float[] { 38, 82, 56 }, new float[] { 74, 83, 57 } })
        {
            BroadTree(row[0], row[1], 0.3f, 1.6f, (int)(row[2]), new TreeOptions { Color = (int)(2907187) });
        }
    }
    private void RailFlora()
    {
        var rows = new List<float[]>();
        var placements = new[] { new float[] { 3.6f, 0.6f, 72 }, new float[] { 4.2f, -0.8f, 71 }, new float[] { 4.8f, 1.8f, 70 }, new float[] { 5.5f, 0.2f, 70 }, new float[] { 6.2f, -1.6f, 70 }, new float[] { 6.8f, 1.2f, 69 }, new float[] { 7.5f, -0.4f, 69 }, new float[] { 8.2f, 2.4f, 69 }, new float[] { 7.4f, -2.6f, 68 }, new float[] { 7.2f, 3, 68 }, new float[] { 1.6f, 0.5f, 76 }, new float[] { 1.9f, -0.9f, 78 }, new float[] { 2.2f, 1.4f, 76 }, new float[] { 2.5f, -1.8f, 77 }, new float[] { 2.8f, 0.2f, 74 }, new float[] { 2, 2.2f, 74 }, new float[] { 2.4f, -2.6f, 76 }, new float[] { 1.7f, -1.6f, 80 }, new float[] { 3, -3, 74 }, new float[] { 3.1f, 2.8f, 74 }, new float[] { 3.4f, 2.2f, 74 }, new float[] { 4, 3.2f, 72 }, new float[] { 5, 4.2f, 70 }, new float[] { 6.4f, 5.4f, 68 }, new float[] { 7.4f, 4.6f, 67 }, new float[] { 7, 6.2f, 66 }, new float[] { 4, 4.9f, 46 }, new float[] { 5, 5.9f, 34 }, new float[] { 6, 7, 22 }, new float[] { 3.5f, 4.4f, 58 }, new float[] { 4, -4.9f, 42 }, new float[] { 5, -5.9f, 30 }, new float[] { 6, -6.9f, 46 }, new float[] { 7.2f, -8, 36 }, new float[] { 4.6f, -5.6f, 56 }, new float[] { 3.6f, -4.4f, 62 }, new float[] { 6, -2.8f, 70 }, new float[] { 7, -4.2f, 69 }, new float[] { 7.4f, -3.4f, 68 }, new float[] { 6.6f, -2, 69 }, new float[] { 5, -4.2f, 66 }, new float[] { 5.6f, -5.2f, 62 }, new float[] { 6.2f, -4.6f, 64 }, new float[] { 6.8f, -5.8f, 60 }, new float[] { 7.2f, -5, 63 }, new float[] { 6.5f, -6.6f, 58 }, new float[] { 7.4f, -6.2f, 61 }, new float[] { 5.8f, -6, 56 } };
        for (int i = 0; i < placements.Length; i += 1)
        {
            var row = placements[i];
            var p = new Vector2(19.2f + 0.1213f * row[0] + 0.9926f * row[1], 80 + 0.9926f * row[0] - 0.1213f * row[1]);
            float leaf_top = 4.38f + Mathf.Tan(0.41f + Mathf.Atan(((50 - row[2]) / 50.0f) * 0.6009f)) * row[0];
            float size = Mathf.Clamp(0.4f + row[0] * 0.12f, 0.6f, 1.1f);
            float lift = Mathf.Clamp(leaf_top - _world.HeightAt(p.X, p.Y) - 0.95f * size, 0, 2.6f);
            rows.Add(new[] { p.X, p.Y, size, 11 + i * 7, lift, (lift > 1.2f ? 3 : ((lift > 0.5f ? 2 : 1))) });
        }
        Rosettes(rows, new Color(unchecked((uint)((2049076 << 8) | 255))));
        foreach (var row in new[] { new float[] { 6, 7.5f, 6.5f, 3.2f, 51 }, new float[] { 6.5f, -8, 5.5f, 2.6f, 52 } })
        {
            BroadTree(19.2f + 0.1213f * row[0] + 0.9926f * row[1], 80 + 0.9926f * row[0] - 0.1213f * row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)(2904640) });
        }
        foreach (var row in new[] { new float[] { 30, 93.5f, 4.4f, 3, 43 }, new float[] { 36.5f, 94.5f, 4.8f, 3.2f, 44 }, new float[] { 42.5f, 93.5f, 4.6f, 3, 45 }, new float[] { 3, 93, 4.4f, 3, 46 }, new float[] { -2, 92, 8, 5, 31 }, new float[] { 56, 94, 8.5f, 5, 32 }, new float[] { -56, 70, 7, 4.5f, 33 }, new float[] { -39, 69, 7.5f, 4.5f, 34 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)(2773056) });
        }
        Rosettes(new[] { new float[] { 33.5f, 91.5f, 1.8f, 1 }, new float[] { 40, 91.5f, 1.8f, 2 }, new float[] { 10, 92.5f, 1.8f, 3 }, new float[] { 34, 80, 1.2f, 4 }, new float[] { 38, 81.5f, 1, 5 } }, new Color(unchecked((uint)((2049076 << 8) | 255))));
        Meadow(new Rect2(6, 74, 28, 14), 6, 0.6f, false, new MeadowOptions { Base = new Vector3(0.07f, 0.18f, 0.15f), Mid = new Vector3(0.14f, 0.3f, 0.19f), Tip = new Vector3(0.27f, 0.42f, 0.23f), SeedHeads = 0.05f });
    }
    private Vector2 VendingPosition(float forward, float side)
    {
        return new Vector2(-64.3f - Mathf.Sin(-1.95f) * forward + Mathf.Cos(-1.95f) * side, 58.6f - Mathf.Cos(-1.95f) * forward - Mathf.Sin(-1.95f) * side);
    }
    private void VendingFlora()
    {
        // Trees and undergrowth framing the active machines and the abandoned machine.
        foreach (var row in new[] { new float[] { -92, 2, 9, 6, 51, 4880954 }, new float[] { -88, 44, 9, 6, 52, 4091450 }, new float[] { -69.2f, 34.6f, 3.5f, 3.5f, 55, 4091450 }, new float[] { -75, 37, 6, 4.2f, 56, 4880954 }, new float[] { -77, 36, 6, 4.2f, 59, 4091450 }, new float[] { -77.5f, 39, 6, 4, 57, 4091450 }, new float[] { -73.5f, 38, 1.2f, 3, 58, 4091450 }, new float[] { -77, 33, 0.8f, 3.2f, 64, 4880954 }, new float[] { -70.8f, 37.5f, 0.3f, 2, 61, 4091450 }, new float[] { -71.5f, 36, 0.3f, 2, 62, 4880954 }, new float[] { -50, 32, 11, 3, 53, 4091450 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)(row[5]), Clusters = (int)((row[4] is 55 or 56 or 59 or 57 ? 150 : 110)), Bark = (int)(2902574) });
        }
        BroadTree(-64, 30.4f, 3.3f, 3.9f, 53, new TreeOptions { Color = (int)(3037748), Bark = (int)(3814440), CardSize = 1, Clusters = (int)(220), ClusterRadius = 0.95f });
        BroadTree(-64.2f, 22.4f, 3.6f, 3.4f, 54, new TreeOptions { Color = (int)(3367482), Bark = (int)(3814440), CardSize = 1, Clusters = (int)(220), ClusterRadius = 0.95f });
        BroadTree(-75, 32.5f, 5, 3, 65, new TreeOptions { Color = (int)(4091450), Bark = (int)(2902574), Clusters = (int)(180), ClusterRadius = 1.1f });
        foreach (var row in new[] { new float[] { -124, 6, 4, 3.5f, 4091450 }, new float[] { -125, 11, 4.5f, 3.8f, 4880954 }, new float[] { -124, 16, 4, 3.5f, 4091450 }, new float[] { -126, 21, 4.5f, 3.8f, 4091450 }, new float[] { -124, 26, 4.2f, 3.5f, 4880954 }, new float[] { -126, 31, 4.5f, 3.8f, 4091450 }, new float[] { -124, 36, 4, 3.5f, 4880954 }, new float[] { -125, 41, 4.5f, 3.8f, 4091450 }, new float[] { -124, 46, 4, 3.5f, 4091450 } })
        {
            BroadTree(row[0], row[1], row[2], row[3], (int)(70 + (int)((row[1] - 6) / 5)), new TreeOptions { Color = (int)(row[4]) });
        }
        Rosettes(new[] { new float[] { -69.4f, 27.6f, 1.4f, 39 }, new float[] { -69, 26, 1.2f, 41 }, new float[] { -69.8f, 29.2f, 1.35f, 43 }, new float[] { -69.2f, 31, 1.2f, 45 }, new float[] { -62.2f, 13.5f, 1.3f, 47 }, new float[] { -62.4f, 37.2f, 1.3f, 49 } }, new Color(unchecked((uint)((3963450 << 8) | 255))));
        Meadow(new Rect2(-84, 6, 16.5f, 38), 3, 0.95f, false, new MeadowOptions { Base = new Vector3(0.3f, 0.44f, 0.19f), Mid = new Vector3(0.52f, 0.65f, 0.27f), Tip = new Vector3(0.74f, 0.79f, 0.38f) });
        Meadow(new Rect2(-67.55f, 11, 0.7f, 28), 16, 0.65f, false, new MeadowOptions { Force = true, Base = new Vector3(0.16f, 0.28f, 0.12f), Mid = new Vector3(0.28f, 0.5f, 0.24f), Tip = new Vector3(0.42f, 0.64f, 0.32f) });
        var groups = new[] { new RosetteGroup { Color = (int)(3366970), Tip = (int)(5933642), Rows = new[] { new float[] { 1.6f, -1, 1.3f }, new float[] { 1.2f, -2, 1.2f }, new float[] { 2.2f, -2.6f, 1.5f }, new float[] { 1.4f, -0.2f, 1 }, new float[] { 1.2f, 0.6f, 0.9f }, new float[] { 3.2f, -3.4f, 1.6f }, new float[] { 1.8f, -0.5f, 1.2f }, new float[] { 2, -1.6f, 1.4f }, new float[] { 2.6f, -3.6f, 1.5f } } }, new RosetteGroup { Color = (int)(3829824), Tip = (int)(7645270), Rows = new[] { new float[] { 0.9f, -1.7f, 1.9f }, new float[] { 1.2f, -2.4f, 1.8f }, new float[] { 1.15f, -0.9f, 0.9f }, new float[] { 1.05f, -0.2f, 0.8f }, new float[] { 1.2f, 0.5f, 0.75f }, new float[] { 1.3f, 1.3f, 0.8f }, new float[] { 0.95f, -1.2f, 0.9f } } }, new RosetteGroup { Color = (int)(3894077), Tip = (int)(0), Rows = new[] { new float[] { 5, 1.5f, 1.6f }, new float[] { 6.5f, 3.5f, 1.7f }, new float[] { 5.8f, 2.6f, 1.4f }, new float[] { 7.2f, 5, 1.6f } } }, new RosetteGroup { Color = (int)(3499580), Tip = (int)(6987346), Rows = new[] { new float[] { 1.5f, -1.9f, 1.7f }, new float[] { 2.1f, -2.5f, 1.9f }, new float[] { 1.25f, -1.6f, 1.4f }, new float[] { 4.8f, -0.6f, 1.8f }, new float[] { 5.3f, -1.5f, 1.7f }, new float[] { 4.4f, -1, 1.9f }, new float[] { 4.6f, 0.1f, 1.7f }, new float[] { 5.6f, -0.9f, 2 }, new float[] { 4.2f, -0.2f, 1.6f } } } };
        foreach (var group in groups)
        {
            var rows = new List<float[]>();
            foreach (var row in group.Rows)
            {
                var p = VendingPosition(row[0], row[1]);
                rows.Add(new float[] { p.X, p.Y, row[2], 100 + (int)(row[0] * 7) + (int)(row[1] * 5) });
            }
            Rosettes(rows, new Color(unchecked((uint)(((int)(group.Color) << 8) | 255))), (group.Tip > 0 ? new Color(unchecked((uint)(((int)(group.Tip) << 8) | 255))) : Colors.Transparent));
        }
        foreach (var row in new[] { new float[] { 6.2f, -3.6f, 1.2f, 1.8f, 63, 2773056, 150, 0.9f, 0.9f }, new float[] { 5.4f, 2.4f, 0, 2, 64, 3103285, 140, 0.9f, 0.9f }, new float[] { 7, 4.6f, 0, 2.2f, 66, 3564090, 140, 0.9f, 0.9f }, new float[] { 11, 8.5f, 5.5f, 3.6f, 68, 3564090, 110, 1.6f, 1.2f }, new float[] { 6, 9.5f, 4.5f, 3.2f, 69, 3103285, 110, 1.6f, 1.2f }, new float[] { -2.4f, -2.4f, 4.5f, 3.4f, 81, 3103285, 14, 1.6f, 1.4f }, new float[] { 0.8f, -2.6f, 5.2f, 1.9f, 83, 3498810, 70, 1.4f, 1 } })
        {
            var p = VendingPosition(row[0], row[1]);
            BroadTree(p.X, p.Y, row[2], row[3], (int)(row[4]), new TreeOptions { Color = (int)(row[5]), Clusters = (int)(row[6]), CardSize = row[7], ClusterRadius = row[8] });
        }
    }
}
