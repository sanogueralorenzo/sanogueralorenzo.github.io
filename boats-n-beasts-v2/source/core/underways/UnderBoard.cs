using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed class UnderBoard
{
    public readonly bool Mirror;
    public readonly (int X,int Y)[] Blocks, Sockets;
    public readonly bool[] Slash=[true,false,true];
    public readonly List<Vector2> Ray=[];
    public int CargoMoves, Reached;
    readonly bool flip,turn;
    static readonly (int,int)[] Glass=[(1,3),(1,1),(3,1)];
    static readonly (int,int)[] Wall=[(1,0),(0,3),(3,3)];
    public UnderBoard(int seed,bool mirror)
    {
        Mirror=mirror;var rng=new Random(seed);flip=rng.Next(2)==1;turn=rng.Next(2)==1;
        Blocks=[(1,2),(3,2)];Sockets=[(2,1),(3,0)];
        if(Mirror){Slash[0]=rng.Next(2)==1;Slash[1]=rng.Next(2)==1;Slash[2]=rng.Next(2)==1;Trace();if(Reached==1){Slash[1]=!Slash[1];Trace();}}
    }
    public Vector2 At((int X,int Y) cell)
    {
        int x=flip?4-cell.X:cell.X,y=turn?4-cell.Y:cell.Y;
        return new((x-2)*.86f,(y-2)*.86f);
    }
    public bool SlantsForward(int i)=>Slash[i]^(flip!=turn);
    public Vector2 GlassAt(int i)=>At(Glass[i]);
    public IEnumerable<Vector2> Walls=>Wall.Select(At);
    public Vector2 Source=>At((-1,3));
    public Vector2 Receiver=>At((3,5));
    public int Matched=>Blocks.Count(b=>Sockets.Contains(b));
    public void Rotate(int index){Slash[index]=!Slash[index];Trace();}
    void Trace()
    {
        Ray.Clear();Reached=0;int x=-1,y=3,dx=1,dy=0;Ray.Add(At((x,y)));
        for(int i=0;i<25;i++)
        {
            x+=dx;y+=dy;
            if(x<0||y<0||x>4||y>4){Ray.Add(At((x,y)));Reached=x==3&&y==5?1:0;return;}
            int k=Array.IndexOf(Glass,(x,y));
            if(k>=0){Ray.Add(At((x,y)));(dx,dy)=Slash[k]?(-dy,-dx):(dy,dx);}
        }
    }
    public bool Shift(int index,Vector2 from,bool hook)
    {
        var b=Blocks[index];var dir=hook?from-At(b):At(b)-from;
        if(dir.LengthSquared()<.035f)return false;
        int dx=0,dy=0;
        if(Math.Abs(dir.X)>=Math.Abs(dir.Y))dx=Math.Sign(dir.X)*(flip?-1:1);else dy=Math.Sign(dir.Y)*(turn?-1:1);
        var n=(X:b.X+dx,Y:b.Y+dy);
        if(n.X<0||n.Y<0||n.X>4||n.Y>4||Wall.Contains(n)||Blocks.Contains(n))return false;
        Blocks[index]=n;CargoMoves++;return true;
    }
}
