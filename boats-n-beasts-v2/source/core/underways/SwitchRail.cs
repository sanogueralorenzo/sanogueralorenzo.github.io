using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class SwitchRail
{
    public readonly bool[] Divert=new bool[7];
    public readonly int[] Manifest;
    public int Delivered,Node=-1,Destination=-1;
    public float Fraction;
    public bool Rolling,Missed;
    public int Next=>Node<0?0:Node<7?Node*2+(Divert[Node]?2:1):-1;
    readonly bool reflect;
    public int Asked=>Manifest[Math.Min(Delivered,Manifest.Length-1)];
    public bool Done=>Delivered==Manifest.Length;
    public SwitchRail(int seed,int depth)
    {
        var rng=new Random(seed);reflect=rng.Next(2)==0;
        int[] bays=Enumerable.Range(0,8).ToArray();rng.Shuffle(bays);
        Manifest=bays[..Math.Min(5,3+depth/2)];for(int i=0;i<7;i++)Divert[i]=rng.Next(2)==0;
    }
    public Vector2 At(int node)
    {
        if(node<0)return new(0,2.65f);int layer=node<1?0:node<3?1:node<7?2:3;
        int count=1<<layer,slot=node-count+1;
        return new((reflect?-1:1)*(slot-(count-1)*.5f)*7f/count,1.67f-layer*1.27f);
    }
    public Vector2 Cart=>Rolling?Vector2.Lerp(At(Node),At(Destination),Fraction):At(Node);
    public bool Launch()
    {
        if(Done)return false;
        if(!Rolling&&Node>=7){Node=-1;Missed=false;}
        if(Rolling)return false;
        Destination=Next;Fraction=0;Rolling=true;return true;
    }
    public void Tick(float dt)
    {
        if(!Rolling)return;float distance=Vector2.Distance(At(Node),At(Destination));Fraction+=dt*1.75f/Math.Max(.01f,distance);
        if(Fraction<1)return;Node=Destination;Fraction=0;
        if(Node>=7){Rolling=false;Missed=Node-7!=Asked;if(!Missed){Delivered++;if(!Done)Node=-1;}return;}
        Destination=Next;
    }
    public void Throw(int i){if(i>=0&&i<7)Divert[i]=!Divert[i];}
    public static string Berth(int i)=>new[]{"Anchor","Bird","Crown","Drum","Eye","Fish","Gull","Hand"}[i];
}
