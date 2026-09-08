using System.Numerics;
namespace Further.Core;
public readonly record struct Decoration(string Asset,Vector2 LocalPosition,float Ground,float Height,float Yaw,float CollisionRadius);
public readonly record struct MeadowTuft(Vector2 Position,float Ground,float Scale,float Yaw);
public static class IslandLayout
{
    public const int TreasureCount=12;
    public static Vector2[][] Routes(Island island)
    {
        float r=island.Radius,meander=(island.Seed%3-1)*.08f;
        Vector2 P(float x,float z)=>island.InteriorPoint(x,z);
        return [
            [island.Landing-island.Center,P(-.12f+meander,-.60f),P(-.23f,-.30f),P(-.17f,0),P(.10f,.16f),P(.32f,.20f)],
            [P(-.23f,-.30f),P(-.43f,-.24f),P(-.63f,-.16f)],
            [P(-.17f,0),P(-.43f,.24f),P(-.60f,.43f)],
            [P(.10f,.16f),P(.49f,.07f),P(.67f,-.27f)],
            [P(.32f,.20f),P(.47f,.37f),P(.48f,.59f)]
        ];
    }
    public static float TrailDistance(Vector2 p,Vector2[][] routes)
    {
        float best=float.MaxValue;
        foreach(var path in routes)for(int i=1;i<path.Length;i++)
        {
            var a=path[i-1];var line=path[i]-a;float t=Math.Clamp(Vector2.Dot(p-a,line)/line.LengthSquared(),0,1);
            best=MathF.Min(best,Vector2.Distance(p,a+line*t));
        }
        return best;
    }
    public static Vector2 Treasure(Island island,int index)
    {
        var paths=Routes(island);if(index>=8)return island.Center+paths[index-7][^1];
        var path=paths[0];float length=0;for(int i=1;i<path.Length;i++)length+=Vector2.Distance(path[i-1],path[i]);
        float along=length*(index+.6f)/8.6f;
        for(int i=1;i<path.Length;i++){float segment=Vector2.Distance(path[i-1],path[i]);if(along<=segment)return island.Center+Vector2.Lerp(path[i-1],path[i],along/segment);along-=segment;}
        return island.Shrine;
    }
    public static IReadOnlyList<Decoration> Scenery(Island island)
    {
        var r=new Random(island.Seed);var result=new List<Decoration>();var routes=Routes(island);
        for(int k=0;k<1100;k++)
        {
            float angle=(float)r.NextDouble()*MathF.Tau,rad=MathF.Sqrt((float)r.NextDouble())*island.Radius*.97f;
            Vector2 p=new(MathF.Cos(angle)*rad,MathF.Sin(angle)*rad);float h=World.Height(island,island.Center+p);
            float pathDistance=TrailDistance(p,routes);
            if(h<.4f || pathDistance<4 || Vector2.Distance(p,island.Shrine-island.Center)<12 || routes.Skip(1).Any(path=>Vector2.Distance(p,path[^1])<7))continue;
            string key;float height;
            if(h<2.8f || k%9==0){key="roundrock";height=1.1f+(float)r.NextDouble()*2.6f;}
            else if(k%5==0){key="bush";height=1+(float)r.NextDouble()*1.3f;}
            else{key="tree";height=7.0f+(float)r.NextDouble()*5.0f;}
            float radius=key switch{"tree"=>.4f,"bush"=>0,_=>height*.48f};
            if(result.Any(d=>Vector2.DistanceSquared(d.LocalPosition,p)<(key=="tree"?26:9)))continue;
            result.Add(new(key,p,h-.1f,height,angle,radius));
        }
        for(int k=0;k<9;k++)
        {
            float a=k/9f*MathF.Tau;Vector2 p=new(MathF.Cos(a)*island.Radius*.77f,MathF.Sin(a)*island.Radius*.77f);
            if(MathF.Abs(p.X)<10)continue;float h=World.Height(island,island.Center+p);float height=2.8f+(k%3)*.6f;result.Add(new("roundrock",p,h-.5f,height,a,height*.48f));
        }
        return result;
    }
    public static IReadOnlyList<MeadowTuft> Meadow(Island island)
    {
        var random=new Random(island.Seed);var result=new List<MeadowTuft>();var routes=Routes(island);
        for(float z=-island.Radius;z<island.Radius;z+=1.35f)for(float x=-island.Radius*1.2f;x<island.Radius*1.2f;x+=1.35f)
        {
            var p=new Vector2(x+(float)random.NextDouble(),z+(float)random.NextDouble());
            float height=World.Height(island,island.Center+p);
            if(height<3 || TrailDistance(p,routes)<2.2f || Vector2.Distance(p,island.Shrine-island.Center)<9 || routes.Skip(1).Any(path=>Vector2.Distance(p,path[^1])<5))continue;
            if(MathF.Sin(x*.07f+island.Seed)*MathF.Cos(z*.11f)<-.4f)continue;
            result.Add(new(p,height-.03f,.35f+(float)random.NextDouble()*.6f,(float)random.NextDouble()*MathF.Tau));
        }
        return result;
    }
    public static Vector2 ResolveObstacles(Vector2 position,Island island,IReadOnlyList<Decoration> scenery)
    {
        Vector2 p=position-island.Center;
        foreach(var d in scenery)
        {
            if(d.CollisionRadius<=0)continue;Vector2 diff=p-d.LocalPosition;float distance=diff.Length(),radius=d.CollisionRadius+.4f;
            if(distance<radius)p=d.LocalPosition+(distance>.001f?diff/distance:Vector2.UnitX)*radius;
        }
        return p+island.Center;
    }
}
