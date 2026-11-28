using Godot;

namespace BoatsNBeasts;

internal partial class QuayMusic : Node
{
    static readonly int[] Melody = [62,0,69,67,65,0,0,0,64,67,69,0,72,69,0,0,
        65,0,69,72,74,72,69,0,67,64,62,0,0,0,0,0];
    static readonly int[] Bass = [50,45,48,43,46,41,45,50];
    AudioStreamPlayer strings = null!, low = null!, bronze = null!;
    float next = 1.3f;
    int pulse;

    public override void _Ready()
    {
        strings = Player(-24,3); low = Player(-27,2); bronze = Player(-16,3);
    }
    AudioStreamPlayer Player(float volume, int voices)
    {
        var player = new AudioStreamPlayer { VolumeDb = volume, MaxPolyphony = voices };
        AddChild(player); return player;
    }
    internal void Ring() { bronze.Stream = QuayTone.Note(74,true); bronze.Play(); }
    public override void _Process(double delta)
    {
        next -= (float)delta;
        if (next > 0) return;
        next = pulse == Melody.Length - 1 ? 7.4f : .44f;
        if (pulse % 4 == 0) { low.Stream = QuayTone.Note(Bass[pulse/4],false); low.Play(); }
        if (Melody[pulse] > 0) { strings.Stream = QuayTone.Note(Melody[pulse],false); strings.Play(); }
        pulse = (pulse+1) % Melody.Length;
    }
}
