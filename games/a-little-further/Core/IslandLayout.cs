using System.Numerics;
namespace Further.Core;
public readonly record struct Decoration(string Asset,Vector2 LocalPosition,float Ground,float Height,float Yaw,float CollisionRadius);
public static class IslandLayout
{
    public static Vector2 Treasure(Island island,int index)
    {
        float t=index/7f;return island.Center+new Vector2(MathF.Sin((t-.85f)*island.Radius*.07f)*island.Radius*.19f,(t-.85f)*island.Radius);
    }
    public static IReadOnlyList<Decoration> Scenery(Island island)
    {
        var r=new Random(island.Seed);var result=new List<Decoration>();
        for(int k=0;k<110;k++)
        {
            float angle=(float)r.NextDouble()*MathF.Tau,rad=MathF.Sqrt((float)r.NextDouble())*island.Radius*.97f;
            Vector2 p=new(MathF.Cos(angle)*rad,MathF.Sin(angle)*rad);float h=World.Height(island,island.Center+p);
            float pathX=MathF.Sin(p.Y*.07f)*island.Radius*.19f;
            if(h<.4f || MathF.Abs(p.X-pathX)<8 || Vector2.Distance(p,island.Shrine-island.Center)<12)continue;
            string key;float height;
            if(h<2.8f || k%4==0){key=k%2==0?"rock":"coast";height=1.3f+(float)r.NextDouble()*3.8f;}
            else if(k%3==0){key="bush";height=1+(float)r.NextDouble()*1.3f;}
            else{key=island.Biome switch{0=>"palm",1=>"pine",_=>"birch"};height=4.2f+(float)r.NextDouble()*3.5f;}
            float radius=key switch{"palm" or "pine" or "birch"=>.32f,"bush"=>0,_=>height*.25f};
            result.Add(new(key,p,h-.1f,height,angle,radius));
        }
        for(int k=0;k<9;k++)
        {
            float a=k/9f*MathF.Tau;Vector2 p=new(MathF.Cos(a)*island.Radius*.77f,MathF.Sin(a)*island.Radius*.77f);
            if(MathF.Abs(p.X)<10)continue;float h=World.Height(island,island.Center+p);float height=3.5f+k%3;result.Add(new("coast",p,h-.5f,height,a,height*.3f));
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
