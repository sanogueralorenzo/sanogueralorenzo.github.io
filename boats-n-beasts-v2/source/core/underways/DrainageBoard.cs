using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class DrainageBoard
{
    public const int Size=4;
    public readonly int[] Joints=new int[16],Turns=new int[16];
    public readonly bool[] Wet=new bool[16],Bolted=new bool[16];
    public readonly int Source;
    public readonly int[] Outlets;
    static readonly (int X,int Y)[] Step=[(0,-1),(1,0),(0,1),(-1,0)];
    public DrainageBoard(int seed)
    {
        var rng=new Random(seed);Source=rng.Next(4)*4;
        List<int> carved=[Source];bool[] reached=new bool[16];reached[Source]=true;
        while(carved.Count<16)
        {
            int at=carved[rng.Next(carved.Count)],dir=rng.Next(4),next=Neighbor(at,dir);
            if(next<0||reached[next])continue;
            Joints[at]|=1<<dir;Joints[next]|=1<<((dir+2)%4);carved.Add(next);reached[next]=true;
        }
        Outlets=carved.Where(i=>i!=Source&&System.Numerics.BitOperations.PopCount((uint)Joints[i])==1).OrderByDescending(i=>carved.IndexOf(i)).Take(3).ToArray();
        foreach(int i in carved)
        {
            Bolted[i]=i==Source||Outlets.Contains(i)||rng.Next(7)==0;
            Turns[i]=Bolted[i]?0:rng.Next(4);
        }
        Flood();
        if(Ready)for(int i=0;i<16&&Ready;i++)if(!Bolted[i])Turn(i);
    }
    public static int Neighbor(int cell,int dir)
    {
        int x=cell%4+Step[dir].X,y=cell/4+Step[dir].Y;return x<0||x>=4||y<0||y>=4?-1:y*4+x;
    }
    public static Vector2 At(int cell)=>new((cell%4-1.5f)*1.04f,(cell/4-1.5f)*1.04f);
    public int Ports(int cell){int value=Joints[cell]<<Turns[cell];return (value|(value>>4))&15;}
    public int Filled=>Outlets.Count(i=>Wet[i]);public bool Ready=>Filled==Outlets.Length;
    public void Turn(int cell){if(Bolted[cell])return;Turns[cell]=(Turns[cell]+1)%4;Flood();}
    void Flood()
    {
        Array.Clear(Wet);var q=new Queue<int>();q.Enqueue(Source);Wet[Source]=true;
        while(q.TryDequeue(out var cell))for(int dir=0;dir<4;dir++)
        {
            int next=Neighbor(cell,dir);
            if(next<0||Wet[next]||(Ports(cell)&(1<<dir))==0||(Ports(next)&(1<<((dir+2)%4)))==0)continue;
            Wet[next]=true;q.Enqueue(next);
        }
    }
}
