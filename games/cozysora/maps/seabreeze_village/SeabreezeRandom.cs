namespace CozySora;

/// <summary>The original Mulberry32 stream, including its exact unsigned wrap and draw order.</summary>
public sealed class SeabreezeRandom
{
    public uint State { get; set; } = 1;
    private uint _seed = 1;
    public uint Seed
    {
        get => _seed;
        set { _seed = value; State = value; }
    }

    public double Randf()
    {
        unchecked
        {
            State += 1831565813u;
            uint mixed = (State ^ (State >> 15)) * (1u | State);
            mixed = (mixed + ((mixed ^ (mixed >> 7)) * (61u | mixed))) ^ mixed;
            return (mixed ^ (mixed >> 14)) / 4294967296.0;
        }
    }

    public float RandfRange(float low, float high) => (float)(low + (high - low) * Randf());
    public int RandiRange(int low, int high) => low + (int)Math.Floor(Randf() * (high - low + 1));
}
