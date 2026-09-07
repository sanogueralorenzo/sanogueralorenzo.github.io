using System.Text.Json;
using Godot;
namespace Further;
// Small data adapter; Unity's serialized curves are read from the private package.
public sealed class SourceAnimation
{
    readonly (float Time,float Value,float In,float Out)[] bob;
    readonly List<(float Time,float[] Values)> wing=[];
    public SourceAnimation()
    {
        using var b=JsonDocument.Parse(File.ReadAllText(Art.Local("headbob.json")));
        bob=b.RootElement.GetProperty("m_Curve").EnumerateArray().Select(k=>(k.GetProperty("time").GetSingle(),k.GetProperty("value").GetSingle(),k.GetProperty("inSlope").GetSingle(),k.GetProperty("outSlope").GetSingle())).ToArray();
        using var w=JsonDocument.Parse(File.ReadAllText(Art.Local("FlapWings.animation.json")));
        var stream=w.RootElement.GetProperty("m_MuscleClip").GetProperty("m_Clip").GetProperty("data").GetProperty("m_StreamedClip").GetProperty("data").EnumerateArray().Select(x=>x.GetUInt32()).ToArray();
        for(int i=0;i<stream.Length;)
        {
            float time=BitConverter.UInt32BitsToSingle(stream[i++]);int count=(int)stream[i++];float[] values=new float[6];
            for(int k=0;k<count;k++){int index=(int)stream[i++];i+=3;float v=BitConverter.UInt32BitsToSingle(stream[i++]);if(index<6)values[index]=v;}
            if(float.IsFinite(time)&&time>=0&&count==6)wing.Add((time,values));
        }
    }
    public float Bob(float time,float speed)
    {
        float interval=.25f-.125f*Math.Clamp(speed/6.3f,0,1);float phase=1-(time/interval%1);
        for(int i=1;i<bob.Length;i++)if(phase<=bob[i].Time)
        {
            var a=bob[i-1];var b=bob[i];float duration=b.Time-a.Time,t=(phase-a.Time)/duration;
            float v=(2*t*t*t-3*t*t+1)*a.Value+(t*t*t-2*t*t+t)*duration*a.Out+(-2*t*t*t+3*t*t)*b.Value+(t*t*t-t*t)*duration*b.In;
            return v*.15f*MathF.Min(speed,1);
        }
        return 0;
    }
    public Vector3 Wings(float time)
    {
        if(wing.Count<2)return Vector3.One;float phase=time%wing[^1].Time;
        for(int i=1;i<wing.Count;i++)if(phase<=wing[i].Time)
        {
            var a=wing[i-1];var b=wing[i];float t=(phase-a.Time)/MathF.Max(.001f,b.Time-a.Time);
            return new(Mathf.Lerp(a.Values[0],b.Values[0],t),Mathf.Lerp(a.Values[1],b.Values[1],t),Mathf.Lerp(a.Values[2],b.Values[2],t));
        }
        return Vector3.One;
    }
}
