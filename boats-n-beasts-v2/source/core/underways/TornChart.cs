using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class TornChart
{
    public readonly int[] Tiles=[1,2,3,4,5,6,7,8,0];
    public int Gap{get;private set;}=8;
    public bool Restored=>Distance(Tiles)==0;
    public int Suggested{get;private set;}=-1;
    readonly Stack<int> shifts=[];
    public TornChart(int seed,int depth)
    {
        var rng=new Random(seed);int previous=-1;
        for(int k=0;k<20+Math.Min(8,depth);k++)
        {
            var moves=Adjacent(Gap).Where(i=>i!=previous).ToArray();previous=Gap;Push(moves[rng.Next(moves.Length)]);
        }
        if(Restored)Push(Adjacent(Gap).First());shifts.Clear();
    }
    public static Vector2 At(int i)=>new((i%3-1)*1.28f,(i/3-1)*1.19f);
    public static IEnumerable<int> Adjacent(int i)
    {
        if(i%3>0)yield return i-1;if(i%3<2)yield return i+1;
        if(i>=3)yield return i-3;if(i<6)yield return i+3;
    }
    static int Distance(int[] tiles)
    {
        int sum=0;for(int i=0;i<9;i++)if(tiles[i]>0){int target=tiles[i]-1;sum+=Math.Abs(i%3-target%3)+Math.Abs(i/3-target/3);}
        return sum;
    }
    static ulong Code(int[] tiles){ulong code=0;foreach(int i in tiles)code=(code<<4)|(uint)i;return code;}
    public bool Push(int i)
    {
        if(!Adjacent(Gap).Contains(i))return false;
        shifts.Push(Gap);(Tiles[Gap],Tiles[i])=(Tiles[i],Tiles[Gap]);Gap=i;Suggested=-1;return true;
    }
    public bool Undo()
    {
        if(!shifts.TryPop(out var index))return false;
        (Tiles[Gap],Tiles[index])=(Tiles[index],Tiles[Gap]);Gap=index;Suggested=-1;return true;
    }
    public int ReadGrain()
    {
        if(Restored)return -1;
        var seen=new HashSet<ulong>();var q=new PriorityQueue<(int[] A,int Hole,int First,int Count),int>();
        q.Enqueue((Tiles,Gap,-1,0),0);
        while(q.TryDequeue(out var node,out _))
        {
            if(!seen.Add(Code(node.A)))continue;
            if(Distance(node.A)==0)return Suggested=node.First;
            foreach(int i in Adjacent(node.Hole))
            {
                var child=(int[])node.A.Clone();(child[i],child[node.Hole])=(child[node.Hole],child[i]);
                int depth=node.Count+1;
                q.Enqueue((child,i,node.First<0?i:node.First,depth),depth+Distance(child));
            }
        }
        return -1;
    }
}
