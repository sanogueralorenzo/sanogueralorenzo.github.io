using Godot;

namespace CozySora;

public partial class CozyPlayer
{
    public AudioStreamPlayer? Audio { get; private set; }
    private AudioStreamGeneratorPlayback? _audioPlayback;
    private Godot.Collections.Dictionary _ambience = new();
    private double _audioTime, _audioNoise, _nextBird = 4;
    private readonly List<SoundEvent> _soundEvents = new();
    private sealed class SoundEvent(string kind, double start, double seed)
    {
        public readonly string Kind = kind;
        public readonly double Start = start, Seed = seed;
        public double Phase;
    }

    private void StartAudio()
    {
        Audio = new AudioStreamPlayer { Stream = new AudioStreamGenerator { MixRate = 22050, BufferLength = .15f }, VolumeDb = -6 };
        AddChild(Audio);
        Audio.Play();
        _audioPlayback = (AudioStreamGeneratorPlayback)Audio.GetStreamPlayback();
    }

    private void PlaySound(string kind)
    {
        if (Audio == null || MenuOpen || ShotMode) return;
        _soundEvents.Add(new(kind, _audioTime, GD.Randf()));
    }

    private double AmbienceValue(string name) => _ambience.TryGetValue(name, out var value) ? value.AsDouble() : 0;

    public override void _Process(double delta)
    {
        if (_audioPlayback == null || MenuOpen) return;
        double windGain = AmbienceValue("wind_gain"), waveBase = AmbienceValue("wave_base"), waveSwell = AmbienceValue("wave_swell");
        var cicadaFrequencies = _ambience.TryGetValue("cicada_frequencies", out var frequencies) ? frequencies.AsVector2() : Vector2.Zero;
        double cicadaGain = AmbienceValue("cicada_gain");
        int frames = _audioPlayback.GetFramesAvailable();
        for (int i = 0; i < frames; i++)
        {
            _audioTime += 1.0 / 22050;
            double noise = GD.RandRange(-1.0, 1.0);
            _audioNoise = _audioNoise * .975 + noise * .025;
            double sea = waveBase + waveSwell * Math.Sin(_audioTime * .55) * Math.Sin(_audioTime * .137 + 1.3);
            double sample = _audioNoise * (windGain + sea * 4);
            double cicada = (Math.Sin(_audioTime * Math.Tau * cicadaFrequencies.X) + Math.Sin(_audioTime * Math.Tau * cicadaFrequencies.Y)) * cicadaGain;
            sample += cicada * (.45 + .55 * Math.Pow(Math.Sin(_audioTime * 33), 2));
            foreach (var sound in _soundEvents)
            {
                double age = _audioTime - sound.Start;
                double envelope = 0, frequency = 0;
                switch (sound.Kind)
                {
                    case "step": sample += noise * Math.Exp(-age * 55) * .028; break;
                    case "wing": sample += age < .28 ? _audioNoise * Math.Sin(Math.Clamp(age / .28, 0, 1) * Math.PI) * .35 : 0; break;
                    case "meow":
                        if (age < .48)
                        {
                            double bend = age < .12 ? double.Lerp(1, 1.45, age / .12) : double.Lerp(1.45, .8, (age - .12) / .36);
                            frequency = (560 + sound.Seed * 100) * bend + Math.Sin(age * Math.Tau * 28) * 18;
                            envelope = Math.Min(age / .05, 1) * Math.Min((.48 - age) / .2, 1) * .03;
                        }
                        break;
                    case "cry":
                    case "bird":
                        double syllable = age % .36;
                        if (age < 1.05 && syllable < .29)
                        {
                            frequency = (1120 + sound.Seed * 160) * (.85 + .4 * Math.Sin(syllable / .29 * Math.PI)) + Math.Sin(age * Math.Tau * 38) * 45;
                            envelope = Math.Sin(syllable / .29 * Math.PI) * (sound.Kind == "cry" ? .023 : .008);
                        }
                        break;
                }
                if (frequency > 0)
                {
                    sound.Phase += frequency * Math.Tau / 22050;
                    sample += (Math.Sin(sound.Phase) + Math.Sin(sound.Phase * 2) * .25 + Math.Sin(sound.Phase * 3) * .15) * envelope;
                }
            }
            _audioPlayback.PushFrame(new Vector2((float)sample, (float)(sample * .97)));
        }
        _soundEvents.RemoveAll(sound => _audioTime - sound.Start >= 1.1);
        if (_ambience.TryGetValue("birds", out var birds) && birds.AsBool() && _audioTime > _nextBird)
        {
            PlaySound("bird");
            _nextBird = _audioTime + GD.RandRange(8.0, 19.0);
        }
    }
}
