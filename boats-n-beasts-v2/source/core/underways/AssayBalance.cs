using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class AssayBalance
{
    public readonly int[] Mass=[1,3,9];
    public readonly int[] Pan=new int[3],Targets;
    public int Stamps;
    public bool Complete=>Stamps>=Targets.Length;
    public int Reading=>Mass[0]*Pan[0]+Mass[1]*Pan[1]+Mass[2]*Pan[2];
    public int Target=>Targets[Math.Min(Stamps,Targets.Length-1)];
    public AssayBalance(int seed,int depth)
    {
        var rng=new Random(seed);int[] weights=[..Enumerable.Range(-13,27).Where(i=>i!=0)];
        rng.Shuffle(weights);Targets=weights[..(depth>2?3:2)];
    }
    public Vector2 At(int i)=>new((i-1)*2.0f,1.0f);
    public void Place(int i,int side){Pan[i]=Pan[i]==side?0:side;}
    public bool Weigh(){if(Complete||Reading!=Target)return false;Stamps++;return true;}
}
