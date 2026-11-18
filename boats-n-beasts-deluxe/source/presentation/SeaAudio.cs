using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

public partial class SeaAudio : Node
{
    internal const int Rate = 22050;
    readonly Dictionary<string, AudioStreamPlayer> cues = new();
    AudioStreamPlayer sea = null!, music = null!;
    AudioStreamSynchronized score = null!;
    AudioStreamWav[] layers = [];
    public Voyage? Voyage { get; set; }
    public bool Ducked { get; set; }
    float rhythm, hunt, underway;
    bool muted;

    public bool Muted
    {
        get => muted;
        set
        {
            muted = value;
            if (sea == null) return;
            if (muted)
            {
                sea.Stop();
                music.Stop();
                foreach (var player in cues.Values) player.Stop();
            }
            else { sea.Play(); music.Play(); }
        }
    }

    public override void _Ready()
    {
        if (DisplayServer.GetName() == "headless") return;
        sea = new() { Name = "Sea", Stream = SeaLoop(), VolumeDb = -25 };
        layers = VoyageScore.Build();
        score = new() { StreamCount = layers.Length };
        for (int i = 0; i < layers.Length; i++)
        {
            score.SetSyncStream(i, layers[i]);
            score.SetSyncStreamVolume(i, i == 0 ? -18 : -60);
        }
        music = new() { Name = "VoyageScore", Stream = score };
        AddChild(sea);
        AddChild(music);

        AddCue("shot", Thump(.12f, 96, .64f));
        AddCue("harpoon", Chime(.18f, [311], .46f));
        AddCue("kill", Thump(.17f, 160, .24f));
        AddCue("hurt", Thump(.26f, 65, .78f));
        AddCue("boostStart", Thump(.23f, 132, .38f));
        AddCue("broadside", Thump(.46f, 66, .93f));
        AddCue("bulwark", Chime(.34f, [110, 165, 220], .56f));
        AddCue("blink", Chime(.42f, [392, 587, 784], .58f));
        AddCue("mineDrop", Thump(.12f, 147, .23f));
        AddCue("coilCast", Chime(.18f, [196, 406, 883], .31f));
        AddCue("arcaneCast", Chime(.22f, [294, 440], .30f));
        AddCue("pufferFuse", Chime(.34f, [293, 322, 384], .64f));
        AddCue("bossVolley", Thump(.36f, 115, .58f));
        AddCue("pufferExplosion", Thump(.38f, 77, .68f));
        AddCue("bossExplosion", Thump(.44f, 58, .8f));
        AddCue("closeCall", Chime(.54f, [494, 659, 880], .68f));
        AddCue("explosion", Thump(.26f, 85, .51f));
        AddCue("chain", Chime(.46f, [440, 587, 660], .58f));
        AddCue("towHooked", Chime(.32f, [220, 330], .56f));
        AddCue("towSnapped", Thump(.18f, 204, .71f));
        AddCue("towDelivered", Chime(.88f, [330, 440, 554, 660], .68f));
        AddCue("treasure", Chime(.55f, [440, 554, 659], .58f));
        AddCue("heal", Chime(.46f, [330, 495], .42f));
        AddCue("repairStart", Chime(.45f, [262, 330], .45f));
        AddCue("repairDone", Chime(.75f, [330, 495, 660], .62f));
        AddCue("level", Chime(.35f, [370, 494], .45f));
        AddCue("comboFitted", Chime(.68f, [370, 494, 740], .62f));
        AddCue("stormshot", Thump(.19f, 227, .63f));
        AddCue("tripwire", Chime(.22f, [263, 210], .47f));
        AddCue("riptide", Chime(.25f, [587, 784], .40f));
        AddCue("upgrade", Chime(.31f, [494, 659], .48f));
        AddCue("beaconStart", Chime(.4f, [262, 330], .37f));
        AddCue("beacon", Chime(.85f, [294, 440, 587, 740], .68f));
        AddCue("boss", Chime(1.25f, [98, 139, 147], .75f));
        AddCue("crownclawWindup", Chime(.44f, [108, 114, 156], .76f));
        AddCue("crownclawGrounded", Thump(.61f, 51, .90f));
        AddCue("enraged", Thump(.54f, 55, .68f));
        AddCue("defeat", Chime(1.1f, [293, 220, 147], .62f));
        AddCue("victory", Chime(1.55f, [392, 494, 587, 784, 988], .72f));
        if (!Muted) { sea.Play(); music.Play(); }
    }

    public override void _Process(double delta)
    {
        if (music == null || Muted) return;
        float motion = 0, pressure = 0, crownclaw = 0;
        if (Voyage is { Mode: not (VoyageMode.Victory or VoyageMode.Defeat) } voyage)
        {
            motion = Mathf.Clamp(voyage.Velocity.Length() / voyage.Speed, 0, 1.45f);
            foreach (var beast in voyage.Enemies)
            {
                if (beast.Health <= 0 || beast.Emerging) continue;
                float distance = System.Numerics.Vector2.Distance(voyage.Position, beast.Position);
                float nearness = Mathf.Clamp((690 - distance) / 570, 0, 1);
                if (beast.Kind == EnemyKind.Leviathan)
                    crownclaw = beast.Health < beast.MaxHealth * .5f ? 1 : .77f;
                else pressure += nearness * (beast.Fuse > 0 ? .52f : .25f);
            }
        }

        float blend = 1 - Mathf.Exp(-(float)delta * 2.15f);
        rhythm = Mathf.Lerp(rhythm, Math.Min(1, pressure + crownclaw * .83f), blend);
        hunt = Mathf.Lerp(hunt, crownclaw, blend);
        underway = Mathf.Lerp(underway, motion, blend);
        float damp = Ducked ? -8 : 0;
        music.VolumeDb = Mathf.Lerp(music.VolumeDb, damp, blend);
        sea.VolumeDb = -25 + underway * 4 + hunt * 2 + music.VolumeDb * .48f;
        score.SetSyncStreamVolume(0, -18 - hunt * 3);
        score.SetSyncStreamVolume(1, LayerVolume(rhythm, -15));
        score.SetSyncStreamVolume(2, LayerVolume(hunt, -14));
    }

    static float LayerVolume(float mix, float peak) => Math.Max(-60, peak + Mathf.LinearToDb(Math.Max(.001f, mix)));

    public override void _ExitTree()
    {
        if (sea == null) return;
        Release(sea);
        Release(music);
        foreach (var layer in layers) layer.Dispose();
        foreach (var player in cues.Values) Release(player);
        cues.Clear();
    }

    static void Release(AudioStreamPlayer player)
    {
        player.Stop();
        var stream = player.Stream;
        player.Stream = null;
        stream?.Dispose();
    }

    public void Play(string cue)
    {
        if (!Muted && cues.TryGetValue(cue, out var player)) player.Play();
    }

    void AddCue(string name, AudioStreamWav wave)
    {
        var player = new AudioStreamPlayer { Name = name, Stream = wave, MaxPolyphony = 3, VolumeDb = -14 };
        cues.Add(name, player);
        AddChild(player);
    }

    static AudioStreamWav Chime(float duration, float[] tones, float volume) => Wave(duration, (frame, _) =>
    {
        float time = frame / (float)Rate;
        float cue = 0;
        for (int i = 0; i < tones.Length; i++)
        {
            float note = time - i * duration * .13f;
            if (note < 0) break;
            float phase = Mathf.Tau * tones[i] * note;
            float envelope = Math.Min(1, note * 110) * MathF.Exp(-note * 5.6f / duration);
            cue += (Mathf.Sin(phase) + .2f * Mathf.Sin(phase * 2.02f)) * envelope;
        }
        return cue * volume * .48f;
    });

    static AudioStreamWav Thump(float duration, float frequency, float volume)
    {
        float softened = 0;
        return Wave(duration, (frame, noise) =>
        {
            float time = frame / (float)Rate;
            softened += (noise - softened) * .24f;
            float phase = Mathf.Tau * frequency * time * (1 - .42f * time / duration);
            float envelope = Math.Min(1, time * 800) * MathF.Exp(-time * 5.5f / duration);
            return (Mathf.Sin(phase) * .7f + softened * .7f) * envelope * volume;
        });
    }

    static AudioStreamWav SeaLoop()
    {
        const float duration = 12;
        float low = 0, high = 0;
        return Wave(duration, (frame, noise) =>
        {
            float time = frame / (float)Rate;
            float phase = Mathf.Tau * time / duration;
            low += (noise - low) * .022f;
            high += (noise - high) * .16f;
            float swell = .37f + .18f * Mathf.Sin(phase * 3) + .12f * Mathf.Sin(phase * 5);
            float fade = Math.Clamp(Math.Min(time, duration - time) * 2, 0, 1);
            return (low * 2.7f + high * .53f) * swell * fade;
        }, true);
    }

    internal static AudioStreamWav Wave(float duration, Func<int, float, float> sample, bool loop = false)
    {
        int frames = (int)(duration * Rate);
        var data = new byte[frames * 2];
        var noise = new Random(47293);
        for (int i = 0; i < frames; i++)
        {
            short value = (short)(Math.Clamp(sample(i, 2 * noise.NextSingle() - 1), -1, 1) * short.MaxValue);
            data[2 * i] = (byte)value;
            data[2 * i + 1] = (byte)(value >> 8);
        }
        return new AudioStreamWav
        {
            Format = AudioStreamWav.FormatEnum.Format16Bits, MixRate = Rate, Data = data,
            LoopMode = loop ? AudioStreamWav.LoopModeEnum.Forward : AudioStreamWav.LoopModeEnum.Disabled,
            LoopEnd = frames
        };
    }
}
