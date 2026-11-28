using Godot;

namespace BoatsNBeasts;

internal static class QuayTone
{
    static readonly Dictionary<(int, bool),AudioStreamWav> Notes = [];
    internal static AudioStreamWav Note(int midi, bool bell)
    {
        if (Notes.TryGetValue((midi,bell), out var note)) return note;
        const int rate = 22050;
        float hz = 440f * MathF.Pow(2, (midi - 69)/12f);
        var bytes = new byte[(int)(rate * (bell ? 2.8f : 1.45f)) * 2];
        for (int i = 0; i < bytes.Length / 2; i++)
        {
            float t = i / (float)rate, phase = Mathf.Tau * hz * t;
            float strike = Mathf.Min(1, t * 110), fade = Mathf.Exp(-t * (bell ? 1.9f : 3.8f));
            float wave = Mathf.Sin(phase) + .37f * Mathf.Sin(phase * (bell ? 2.43f : 2)) * Mathf.Exp(-t * 2)
                + .17f * Mathf.Sin(phase * (bell ? 4.18f : 3)) * Mathf.Exp(-t * 4);
            short sample = (short)(wave * strike * fade * 18500);
            bytes[i*2] = (byte)sample; bytes[i*2+1] = (byte)(sample >> 8);
        }
        return Notes[(midi,bell)] = new AudioStreamWav { Format = AudioStreamWav.FormatEnum.Format16Bits,
            MixRate = rate, Data = bytes };
    }
}
