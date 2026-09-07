using Godot;
using CozySora.Water;
using NVector2 = System.Numerics.Vector2;

namespace CozySora;

/// <summary>Godot adapter: generated bathymetry, render geometry and uniforms share one C# wave clock.</summary>
public partial class CozyWaterSurface : Node3D
{
    private const int DepthResolution = 257;
    private WaterSpectrum _spectrum = null!;
    private CozyWaterProfile _profile = null!;
    private ShaderMaterial _material = null!;
    private MeshInstance3D _mesh = null!;
    private Rect2 _bounds, _depthBounds;
    private float[] _depth = [];
    private double _seconds;
    private bool _ocean;
    public float MeanHeight { get; private set; }

    public static CozyWaterSurface Create(CozyMap map, Rect2 bounds, float level, Func<float, float, float> ground,
        CozyWaterProfile profile, CozyAtmosphere atmosphere, bool ocean = false)
    {
        var water = new CozyWaterSurface { Name = ocean ? "Shared ocean" : "Shared shallow water", MeanHeight = level, _bounds = bounds, _profile = profile, _ocean = ocean, ProcessPhysicsPriority = -20 };
        water._spectrum = new(profile.Amplitude, profile.WavelengthScale, profile.Swell);
        water._depthBounds = ocean ? new Rect2(new(map.FlightBounds.Position.X, map.FlightBounds.Position.Z), new(map.FlightBounds.Size.X, map.FlightBounds.Size.Z)).Grow(96) : bounds;
        var depthImage = Image.CreateEmpty(DepthResolution, DepthResolution, false, Image.Format.Rf);
        water._depth = new float[DepthResolution * DepthResolution];
        for (int z = 0; z < DepthResolution; z++) for (int x = 0; x < DepthResolution; x++)
        {
            var at = water._depthBounds.Position + water._depthBounds.Size * new Vector2(x, z) / (DepthResolution - 1);
            float depth = Mathf.Clamp(level - ground(at.X, at.Y), -60, 80);
            water._depth[z * DepthResolution + x] = depth;
            depthImage.SetPixel(x, z, new(depth, 0, 0));
        }
        water._material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shared/water/water.gdshader") };
        var m = water._material;
        var shapes = water._spectrum.Waves.Select(w => new Vector4(w.Direction.X, w.Direction.Y, w.Amplitude, w.Steepness)).ToArray();
        var phases = water._spectrum.Waves.Select(w => new Vector3(w.Number, w.Speed, w.Phase)).ToArray();
        m.SetShaderParameter("wave_shape", shapes); m.SetShaderParameter("wave_phase", phases);
        m.SetShaderParameter("bathymetry", ImageTexture.CreateFromImage(depthImage)); depthImage.Dispose();
        m.SetShaderParameter("depth_bounds", new Vector4(water._depthBounds.Position.X, water._depthBounds.Position.Y, water._depthBounds.Size.X, water._depthBounds.Size.Y));
        m.SetShaderParameter("water_bounds", new Vector4(bounds.Position.X, bounds.Position.Y, bounds.End.X, bounds.End.Y));
        m.SetShaderParameter("deep_color", profile.DeepColor); m.SetShaderParameter("scatter_color", profile.ScatterColor);
        m.SetShaderParameter("absorption", profile.Absorption); m.SetShaderParameter("fog_color", atmosphere.FogColor);
        m.SetShaderParameter("wind", profile.Wind); m.SetShaderParameter("ripple_strength", profile.RippleStrength);
        m.SetShaderParameter("roughness", profile.Roughness); m.SetShaderParameter("optical_depth_min", profile.MinimumOpticalDepth);
        m.SetShaderParameter("shore_damping", profile.ShoreDampingDepth); m.SetShaderParameter("foam_strength", profile.FoamStrength);
        m.SetShaderParameter("wave_height_max", water._spectrum.MaximumHeight);
        m.SetShaderParameter("ocean_surface", ocean);
        var sun = map.GetChildren().OfType<DirectionalLight3D>().FirstOrDefault(n => n.Name == "SummerSun");
        m.SetShaderParameter("sun_direction", sun?.GlobalBasis.Z ?? new Vector3(-.55f, .7f, -.38f).Normalized());
        Mesh mesh;
        if (ocean)
        {
            var geometry = WaterMesh.Ocean();
            var arrays = new Godot.Collections.Array(); arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex] = geometry.Vertices.Select(v => new Vector3(v.X, v.Y, v.Z)).ToArray();
            arrays[(int)Mesh.ArrayType.Normal] = Enumerable.Repeat(Vector3.Up, geometry.Vertices.Length).ToArray();
            // The portable topology is counter-clockwise; Godot front faces are clockwise.
            for (int i = 0; i < geometry.Indices.Length; i += 3) (geometry.Indices[i + 1], geometry.Indices[i + 2]) = (geometry.Indices[i + 2], geometry.Indices[i + 1]);
            arrays[(int)Mesh.ArrayType.Index] = geometry.Indices;
            var surface = new ArrayMesh(); surface.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays); mesh = surface;
        }
        else mesh = new PlaneMesh { Size = bounds.Size, SubdivideWidth = Mathf.Clamp((int)bounds.Size.X * 2, 8, 160), SubdivideDepth = Mathf.Clamp((int)bounds.Size.Y * 2, 8, 160) };
        water._mesh = new MeshInstance3D { Mesh = mesh, MaterialOverride = m, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off, ExtraCullMargin = water._spectrum.MaximumHeight + 2 };
        water.AddChild(water._mesh);
        water._mesh.Position = new(bounds.GetCenter().X, level, bounds.GetCenter().Y);
        map.AddChild(water); map.WaterSurfaces.Add(water);
        return water;
    }

    public override void _PhysicsProcess(double delta)
    {
        _seconds += delta;
        _material.SetShaderParameter("water_time", (float)_seconds);
        if (_ocean && GetViewport().GetCamera3D() is { } camera)
        {
            var at = camera.GlobalPosition;
            _mesh.GlobalPosition = new(Mathf.Round(at.X * 2) * .5f, MeanHeight, Mathf.Round(at.Z * 2) * .5f);
        }
    }

    public float DepthAt(float x, float z)
    {
        var uv = (new Vector2(x, z) - _depthBounds.Position) / _depthBounds.Size;
        if (uv.X < 0 || uv.Y < 0 || uv.X > 1 || uv.Y > 1) return _ocean ? 48 : -1;
        float gx = uv.X * (DepthResolution - 1), gz = uv.Y * (DepthResolution - 1);
        int ix = Math.Min((int)gx, DepthResolution - 2), iz = Math.Min((int)gz, DepthResolution - 2);
        float sampled = Mathf.Lerp(Mathf.Lerp(_depth[iz * DepthResolution + ix], _depth[iz * DepthResolution + ix + 1], gx - ix),
            Mathf.Lerp(_depth[(iz + 1) * DepthResolution + ix], _depth[(iz + 1) * DepthResolution + ix + 1], gx - ix), gz - iz);
        float edge = Mathf.Min(Mathf.Min(uv.X, uv.Y), Mathf.Min(1 - uv.X, 1 - uv.Y));
        return _ocean ? Mathf.Lerp(48, sampled, Mathf.SmoothStep(0, .18f, edge)) : sampled;
    }

    public float HeightAt(float x, float z)
    {
        if (!_bounds.HasPoint(new(x, z)) || DepthAt(x, z) <= .002f) return float.NegativeInfinity;
        NVector2 parameter = new(x, z);
        // Invert horizontal Gerstner displacement so buoyancy samples the rendered world position.
        for (int i = 0; i < 4; i++)
        {
            float attenuation = Mathf.SmoothStep(0, _profile.ShoreDampingDepth, Mathf.Max(0, DepthAt(parameter.X, parameter.Y)));
            parameter = new NVector2(x, z) - _spectrum.Evaluate(parameter, _seconds).Displacement * attenuation;
        }
        return MeanHeight + _spectrum.Evaluate(parameter, _seconds).Height * Mathf.SmoothStep(0, _profile.ShoreDampingDepth, Mathf.Max(0, DepthAt(parameter.X, parameter.Y)));
    }
}
