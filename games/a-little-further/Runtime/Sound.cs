using Godot;
namespace Further;
public partial class Sound : Node
{
    readonly AudioStreamPlayer[] voices=new AudioStreamPlayer[8];
    AudioStreamPlayer sea=null!,music=null!;
    readonly AudioStreamWav[] cues=new AudioStreamWav[5];
    int voice;
    public override void _Ready()
    {
        for(int i=0;i<voices.Length;i++){voices[i]=new(){VolumeDb=-18};AddChild(voices[i]);}
        for(int i=0;i<4;i++)cues[i]=Tone(i);cues[4]=Bell();
        sea=new(){Stream=Sea(),VolumeDb=-29};AddChild(sea);sea.Play();
        music=new(){Stream=Music(),VolumeDb=-28};AddChild(music);music.Play();
    }
    bool stopped;
    public override void _ExitTree()=>Shutdown();
    public void Shutdown()
    {
        if(stopped)return;stopped=true;
        foreach(var player in voices){if(player==null)continue;player.Stop();player.Stream=null;}
        foreach(var player in new[]{sea,music})
        {
            if(player==null)continue;player.Stop();var stream=player.Stream;player.Stream=null;stream?.Dispose();
        }
        foreach(var cue in cues)cue?.Dispose();
    }
    public void Cue(int kind){var p=voices[voice++%voices.Length];p.Stream=cues[kind];p.PitchScale=1+(voice%5-2)*.02f;p.Play();}
    public void SetSea(float speed){sea.VolumeDb=-31+Math.Clamp(speed,0,1)*8;}
    static AudioStreamWav Build(float[] samples,bool loop=false)
    {
        byte[] data=new byte[samples.Length*2];for(int i=0;i<samples.Length;i++){short v=(short)(Math.Clamp(samples[i],-1,1)*32767);data[i*2]=(byte)v;data[i*2+1]=(byte)(v>>8);}
        return new(){Format=AudioStreamWav.FormatEnum.Format16Bits,MixRate=22050,Stereo=false,Data=data,LoopMode=loop?AudioStreamWav.LoopModeEnum.Forward:AudioStreamWav.LoopModeEnum.Disabled,LoopBegin=0,LoopEnd=samples.Length};
    }
    static AudioStreamWav Tone(int kind)
    {
        int n=kind==0?15000:kind==1?6500:3500;var data=new float[n];var r=new Random(kind);
        for(int i=0;i<n;i++){float t=i/22050f,env=MathF.Exp(-t*(kind<2?10:35));float freq=kind switch{0=>i<n/2?440:660,1=>880,2=>180-300*t,_=>80};data[i]=(MathF.Sin(Mathf.Tau*freq*t)*.5f+(kind>=2?((float)r.NextDouble()*2-1)*.3f:MathF.Sin(Mathf.Tau*freq*2*t)*.12f))*env;}
        return Build(data);
    }
    static AudioStreamWav Bell()
    {
        var data=new float[22050*3];float[] ratios=[1,2.01f,2.74f,4.07f];
        for(int i=0;i<data.Length;i++){float t=i/22050f;for(int j=0;j<ratios.Length;j++)data[i]+=MathF.Sin(Mathf.Tau*220*ratios[j]*t)*MathF.Exp(-t*(1.2f+j*.6f))*.26f/(j+1);}
        return Build(data);
    }
    static AudioStreamWav Sea()
    {
        var data=new float[22050*8];var r=new Random(31);float low=0;
        for(int i=0;i<data.Length;i++){low+=(float)(r.NextDouble()*2-1-low)*.035f;data[i]=low*(.5f+.25f*MathF.Sin(i/22050f*Mathf.Tau/8));}return Build(data,true);
    }
    static AudioStreamWav Music()
    {
        var data=new float[22050*32];int[] notes=[50,57,62,66,57,64,69,66,47,54,59,62,45,52,57,61];
        for(int n=0;n<32;n++){float frequency=440*MathF.Pow(2,(notes[n%16]-69)/12f);int start=n*22050;
            for(int j=0;j<22050*3&&start+j<data.Length;j++){float t=j/22050f;float env=(1-MathF.Exp(-t*35))*MathF.Exp(-t*2);data[start+j]+=(MathF.Sin(Mathf.Tau*frequency*t)+.32f*MathF.Sin(Mathf.Tau*frequency*2*t))*.16f*env;}}
        return Build(data,true);
    }
}
