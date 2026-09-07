using Godot;

namespace CozySora;

/// <summary>Map-owned generation and ground queries consumed by the shared application and player.</summary>
public partial class CozyMap : Node3D
{
    [Signal] public delegate void LoadProgressEventHandler(string message, float fraction);
    public Dictionary<string, float[]> ScenicViews { get; protected set; } = new();
    public Godot.Collections.Dictionary Ambience { get; protected set; } = new();
    public CozyAtmosphere? Atmosphere { get; internal set; }
    public List<CozyWaterSurface> WaterSurfaces { get; } = new();
    public string GenerationSignature { get; protected set; } = "";
    public bool SupportsSurfaceTraversal { get; protected set; }
    public Aabb FlightBounds { get; protected set; } = new(new(-135, -30, -95), new(270, 140, 213));

    public virtual Task Build() => Task.CompletedTask;
    public virtual void SetPaused(bool value) { }
    public virtual float HeightAt(float x, float z) => 0;
    public virtual bool Walkable(float x, float z) => true;

    public float WaterSupportHeight(float x, float z, float ground)
    {
        foreach (var water in WaterSurfaces)
        {
            float height = water.HeightAt(x, z);
            if (float.IsFinite(height) && ground <= water.MeanHeight + .075f) return height;
        }
        return ground;
    }

    protected void ReportProgress(string message, float fraction) => EmitSignal(SignalName.LoadProgress, message, fraction);
    protected async Task NextFrame() => await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
}
