using Godot;

namespace BoatsNBeasts;

internal enum WatchTempo { Harbor, Sailing, Landing, Danger }

internal partial class TideScore : AudioStreamPlayer
{
    internal Func<(int Region,WatchTempo Tempo)> Hear=null!;
    internal bool Quiet {get;private set;}
    const int Rate=22050;
    const string Settings="user://soundings.cfg";
    static readonly int[][] Lines=[
        [0,2,4,2,5,4,2,0], [0,0,3,2,5,3,4,2], [2,4,3,1,0,2,4,5], [4,3,2,0,1,3,2,0],
        [0,2,3,5,6,4,2,1], [4,2,0,3,2,5,4,0], [1,4,2,0,4,3,1,0], [0,3,5,4,2,1,2,0],
        [2,1,0,3,5,4,3,1], [0,4,3,1,2,5,2,0], [4,5,3,2,0,1,2,3], [0,2,1,0,4,2,1,0],
        [5,4,2,0,3,5,4,2], [0,3,2,0,1,3,5,4], [3,2,0,1,3,4,2,0], [0,2,4,5,3,2,1,0]];
    static readonly int[][] Scales=[[0,2,4,5,7,9,10],[0,2,3,5,7,9,10],[0,2,4,6,7,9,11],[0,2,3,5,7,8,10]];
    static readonly int[] Roots=[50,55,53,48,52,50,48,53,55,50,53,48,52,50,48,55];
    readonly Vector2[] block=new Vector2[256];
    AudioStreamGeneratorPlayback? playback;
    readonly Voice fiddle=new(.99981f, .27f),mandolin=new(.99974f,.44f),bass=new(.99986f,.19f),drum=new(.99945f,.15f);
    int beat,remaining;
    float volume,beatLength=.48f;
    public override void _Ready()
    {
        var settings=new ConfigFile();
        if(settings.Load(Settings)==Error.Ok)Quiet=settings.GetValue("music","quiet",false).AsBool();
        Stream=new AudioStreamGenerator{MixRate=Rate,BufferLength=.24f};
        VolumeDb=-15;Play();playback=GetStreamPlayback() as AudioStreamGeneratorPlayback;
    }
    internal void Toggle()
    {
        Quiet=!Quiet;
        var settings=new ConfigFile();settings.SetValue("music","quiet",Quiet);settings.Save(Settings);
    }
    public override void _Process(double delta)
    {
        if(playback==null)return;
        var (region,tempo)=Hear();
        int filled=Math.Min(24,playback.GetFramesAvailable()/block.Length);
        for(int n=0;n<filled;n++)
        {
            for(int i=0;i<block.Length;i++)
            {
                if(remaining<=0)Strike(Math.Clamp(region,0,15),tempo);
                remaining--;
                float melody=fiddle.Next(),strings=mandolin.Next(),foot=bass.Next(),pulse=drum.Next();
                volume+=( (Quiet?0:1)-volume)*.00030f;
                block[i]=new Vector2(foot+pulse+strings*.64f+melody,foot+pulse+strings+melody*.75f)*volume;
            }
            playback.PushBuffer(block);
        }
    }
    void Strike(int region,WatchTempo tempo)
    {
        float target=tempo switch{ WatchTempo.Harbor=>.47f,WatchTempo.Sailing=>.34f,WatchTempo.Landing=>.30f,_=>.237f };
        beatLength=Mathf.Lerp(beatLength,target,.18f);
        remaining=(int)(Rate*beatLength*(beat%2==0?1.04f:.96f));
        int phrase=beat/16,bar=beat/8,step=beat%8,section=phrase%8;
        var scale=Scales[region%4];var notes=Lines[region];
        int root=Roots[region]+((bar%8) switch {2 or 3=>-5,4=>-3,5=>2,_=>0});
        if(step==0 || step==4 && tempo!=WatchTempo.Harbor)bass.At(root-12+(step==4?7:0),.20f);
        int degree=notes[(step+((section is 2 or 5)?3:0))%8];
        if(tempo==WatchTempo.Danger || (step+bar)%3!=1 && section!=6)
            mandolin.At(root+scale[degree],tempo==WatchTempo.Harbor?.11f:.16f);
        if((step==0||step==3||step==6) && section is not (3 or 6) && (bar%4!=3||step==0))
            fiddle.At(root+12+scale[notes[(step/3+phrase+region)%8]],tempo==WatchTempo.Danger?.11f:.076f);
        if(tempo!=WatchTempo.Harbor && (step%4==0||step==6 && tempo==WatchTempo.Danger))drum.At(step==0?32:40,.15f);
        beat++;
    }
    public override void _ExitTree()
    {
        Stop();playback?.Dispose();playback=null;Stream=null;
    }
    sealed class Voice(float decay,float harmonic)
    {
        double phase,frequency;
        float envelope,attack;
        internal void At(int note,float gain)
        {
            phase=0;frequency=Math.Tau*440*Math.Pow(2,(note-69)/12d)/Rate;
            envelope=gain;attack=0;
        }
        internal float Next()
        {
            if(envelope<.00015f)return 0;
            phase+=frequency;if(phase>=Math.Tau)phase-=Math.Tau;
            attack=Math.Min(1,attack+.007f);envelope*=decay;
            return (float)(Math.Sin(phase)+harmonic*Math.Sin(phase*2)+.065*Math.Sin(phase*3))*envelope*attack;
        }
    }
}
