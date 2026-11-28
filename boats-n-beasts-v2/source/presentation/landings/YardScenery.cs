using BoatsNBeasts.Core;
using Godot;
using N2=System.Numerics.Vector2;

namespace BoatsNBeasts;

internal static class YardScenery
{
    public const float Level=ShoreSculpture.Floor;
    static readonly Color Wood=new("8b634d"),Steel=new("484959"),Ivory=new("ebdcba");
    public static Node3D District(LandingYard yard,int seed)
    {
        var root=new Node3D();var region=yard.Region;
        var random=new Random(unchecked(seed+yard.District*64231));
        void Land(N2 center,float rx,float rz,bool large)
        {
            var b=new ActorGeometry();
            Color rock=new(region.Rock),sand=new(region.Ground),trim=new(region.Trim);
            const int count=33;
            var top=new Vector3[count];var low=new Vector3[count];var foot=new Vector3[count];
            for(int i=0;i<count;i++)
            {
                float a=Mathf.Tau*i/count,variation=random.NextSingle()*.07f;
                Vector3 P(float scale,float height)=>new(MathF.Cos(a)*rx*scale,height,MathF.Sin(a)*rz*scale);
                top[i]=P(1+variation,Level); low[i]=P(1.08f+variation,.24f+random.NextSingle()*.07f);foot[i]=P(1.16f+variation,-.19f);
            }
            b.Polygon(top,sand,Vector3.Up);
            for(int i=0;i<count;i++)
            {
                int k=(i+1)%count;var outward=(top[i] with{Y=0}).Normalized();var tint=rock.Lightened(random.NextSingle()*.10f);
                b.Polygon([top[i],top[k],low[k],low[i]],tint.Lightened(.10f),outward+Vector3.Up*.55f);
                b.Polygon([low[i],low[k],foot[k],foot[i]],tint,outward);
            }
            int n=large?80:28;
            for(int i=0;i<n;i++)
            {
                float a=random.NextSingle()*Mathf.Tau,d=MathF.Sqrt(random.NextSingle())*.92f;
                var p=new Vector3(MathF.Cos(a)*rx*d,Level+.006f,MathF.Sin(a)*rz*d);
                float spread=.04f+.17f*random.NextSingle();
                for(int j=0;j<2+i%3;j++)
                {
                    var end=p+new Vector3(spread+j*.028f,0,-spread*.43f);
                    b.Polygon([p,end,p+new Vector3(.015f,0,.013f)],sand.Darkened(.18f),Vector3.Up);
                    p+=new Vector3(.035f,0,.034f);
                }
            }
            for(int i=0;i<8;i++)
            {
                float a=(i+.35f)*Mathf.Tau/8;var p=new Vector3(MathF.Cos(a)*rx*.96f,Level,MathF.Sin(a)*rz*.96f);
                if(Math.Abs(p.X)<1.55f||random.NextSingle()<.30f)continue;
                b.Sphere(p,new(.28f,.16f+random.NextSingle()*.22f,.25f),rock.Lightened(.12f),7,4);
            }
            if(large&&region.Climate==IslandClimate.Kiln)
                for(int i=-1;i<=1;i+=2)
                {
                    b.Tube([new(i*.48f,Level+.016f,rz*.72f),new(i*.48f,Level+.016f,rz*.12f)],.026f,trim,5);
                    for(int j=0;j<5;j++)b.RoundBox(new(0,Level+.013f,rz*(.14f+j*.14f)),new(1.31f,.026f,.074f),.01f,Wood);
                }
            var terrain=ShoreSculpture.Bake(b);var position=yard.World(center);terrain.Position=new(position.X,0,position.Y);root.AddChild(terrain);
        }
        Land(N2.Zero,5.24f,3.75f,true);
        foreach(var station in QuayPaths.Bells)Land(station,2.72f,2.43f,false);
        Land(QuayPaths.Summit,5.24f,3.75f,true);
        for(int i=0;i<QuayPaths.Bridges.Length;i++)
        {
            var (a,b)=QuayPaths.Bridges[i];
            if(i!=yard.BrokenBridge||yard.Repaired)root.AddChild(ShoreSculpture.Causeway(yard.World(a),yard.World(b)));
            else
            {
                root.AddChild(ShoreSculpture.Causeway(yard.World(a),yard.World(N2.Lerp(a,b,.38f))));
                root.AddChild(ShoreSculpture.Causeway(yard.World(N2.Lerp(a,b,.62f)),yard.World(b)));
            }
        }
        root.AddChild(ShoreSculpture.Causeway(new(-2.4f,2.75f),new(-2.4f,4.55f)));
        void Place(Node3D node,N2 p,float height=Level)
        {var at=yard.World(p);node.Position=new(at.X,height,at.Y);root.AddChild(node);}
        var boat=ActorArt3D.ShoreSkiff();Place(boat,QuayPaths.Dock+new N2(-1.51f,.13f),.03f);
        Place(Workshop(region,yard.District),new(2.75f,-1.76f));
        Place(Workshop(region,yard.District+1),QuayPaths.Summit+new N2(.5f,-2.91f));
        for(int i=0;i<2;i++)
        {
            var p=QuayPaths.Bells[i];
            Place(Station(region,yard.Options[i]),p+new N2(0,-1.57f));
            if(region.Climate==IslandClimate.Kiln)
            {
                Place(FiringRack(i+yard.District),p+new N2(i==0?-1.46f:1.46f,.72f));
                var unfired=ClayFerry();unfired.RotationDegrees=new(0,56,0);
                Place(unfired,p+new N2(i==0?-1.34f:1.34f,-.91f),Level+.17f);
            }
            else Place(Workshop(region,i+yard.District+1),p+new N2(i==0?-1.62f:1.62f,.80f));
        }
        Place(Tarp(new Color(region.Cloth)),LandingYard.Camp);
        if(region.Climate==IslandClimate.Kiln)
            for(int i=0;i<3;i++)
            {
                var p=QuayPaths.Summit+new N2(4.39f+i*.37f,.72f-i*.89f);
                var ferry=ClayFerry();ferry.RotationDegrees=new(0,20+i*9,0);Place(ferry,p,.09f);
            }
        return root;
    }
    static MeshInstance3D FiringRack(int batch)
    {
        var b=new ActorGeometry();Color terracotta=new("b96e50"),ash=new("5b5157");
        foreach(int sign in new[]{-1,1})b.Tube([new(sign*.50f,0,0),new(sign*.50f,1.26f,0)],.060f,Wood,7);
        for(int level=0;level<2;level++)
        {
            float y=.27f+level*.49f;b.RoundBox(new(0,y,0),new(1.17f,.073f,.44f),.014f,Wood);
            for(int i=-1;i<=1;i++)
            {
                var p=new Vector3(i*.32f,y+.13f,.016f);
                if((batch+level)%2==0)
                {
                    b.Sphere(p,new(.13f,.15f,.13f),terracotta.Lightened(i*.03f+.07f),8,5);
                    b.Ring(p+Vector3.Up*.11f,.094f,.026f,new("dc956a"));
                    b.Sphere(p+Vector3.Up*.113f,new(.082f,.012f,.082f),ash);
                }
                else for(int k=0;k<3;k++)b.RoundBox(p+new Vector3(0,-.06f+k*.05f,0),new(.24f,.045f,.26f),.014f,terracotta);
            }
        }
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D ClayFerry()
    {
        var b=new ActorGeometry();Color clay=new("aa6246"),rim=new("d88c5f");
        Vector3[] Row(float y,float half,float end)=>[new(0,y,-end),new(-half,y,-end*.59f),new(-half,y,end*.61f),new(-half*.60f,y,end),new(half*.60f,y,end),new(half,y,end*.61f),new(half,y,-end*.59f)];
        b.Loft([Row(-.11f,.11f,.57f),Row(.12f,.25f,.78f),Row(.19f,.25f,.8f)],[clay,rim]);
        b.Polygon(Row(.13f,.22f,.73f),clay.Darkened(.29f),Vector3.Up);
        foreach(float z in new[]{-.39f,0,.39f})b.RoundBox(new(0,.19f,z),new(.43f,.032f,.073f),.008f,rim);
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D Tarp(Color cloth)
    {
        var b=new ActorGeometry();
        for(int i=-1;i<=1;i+=2)b.Tube([new(i*.54f,0,-.29f),new(i*.54f,1.13f,-.29f)],.046f,Wood,6);
        for(int i=0;i<6;i++)
        {
            float x=-.66f+i*.22f;
            b.Polygon([new(x,1.21f,-.62f),new(x+.221f,1.21f,-.62f),new(x+.221f,1.03f,.13f),new(x,1.03f,.13f)],i%2==0?cloth:Ivory,Vector3.Up);
        }
        b.RoundBox(new(0,.45f,-.21f),new(.99f,.12f,.47f),.023f,Wood);
        b.Sphere(new(.17f,.56f,-.20f),new(.13f,.10f,.14f),new("c7794f"));
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D Workshop(LandingRegion region,int variant)
    {
        var b=new ActorGeometry();Color rock=new(region.Rock),trim=new(region.Trim),cloth=new(region.Cloth);
        if(region.Climate==IslandClimate.Kiln)
        {
            b.Sphere(new(0,.48f,0),new(.90f,.79f,.71f),cloth.Darkened(.12f),10,6);
            b.Tube([new(0,.75f,0),new(0,1.32f,0)],[.42f,.27f],rock,9);
            b.Ring(new(0,1.31f,0),.29f,.055f,trim);
            b.Sphere(new(0,.28f,.59f),new(.39f,.35f,.12f),Steel);
            b.Sphere(new(0,.21f,.669f),new(.30f,.21f,.07f),new("f49850"));
            for(int i=-2;i<=2;i++)b.Tube([new(i*.103f,.038f,.741f),new(i*.103f,.42f-Math.Abs(i)*.056f,.742f)],.019f,Steel);
            for(int i=0;i<11;i++){float a=i*Mathf.Tau/11;b.RoundBox(new(.82f*MathF.Cos(a),.07f,.65f*MathF.Sin(a)),new(.25f,.14f,.25f),.025f,rock);}
        }
        else if(region.Climate==IslandClimate.Delta||region.Climate==IslandClimate.Loom)
        {
            foreach(int s in new[]{-1,1})b.Tube([new(s*.69f,0,0),new(s*.67f,1.48f,0)],.076f,Wood);
            b.Tube([new(-.84f,1.38f,0),new(.84f,1.38f,0)],.075f,trim);
            for(int i=0;i<8;i++)
            {
                float x=-.64f+i*.16f;
                b.Polygon([new(x,1.34f,0),new(x+.15f,1.34f,0),new(x+.14f,.39f,.03f+i%2*.08f),new(x,.42f,.03f)],i%3==0?cloth:Ivory,Vector3.Back);
            }
        }
        else if(region.Climate==IslandClimate.Orchard)
        {
            b.Tube([new(0,0,0),new(-.12f,.69f,0),new(.1f,1.48f,0)],[.20f,.16f,.10f],Wood);
            for(int i=0;i<7;i++)
            {
                float a=i*Mathf.Tau/7;var tip=new Vector3(.57f*MathF.Cos(a),1.4f+(i%2)*.21f,.53f*MathF.Sin(a));
                b.Tube([new(0,1.02f,0),tip],[.096f,.041f],Wood);
                b.Sphere(tip,new(.45f,.25f,.38f),new("74915e"),7,4);
                b.Tube([tip,tip-Vector3.Up*.38f],.016f,Wood);b.Sphere(tip-Vector3.Up*.46f,new(.14f,.20f,.14f),trim);
            }
        }
        else if(region.Climate==IslandClimate.Reef)
        {
            for(int i=0;i<8;i++){float a=i*Mathf.Tau/8;var p=new Vector3(MathF.Cos(a)*.53f,0,MathF.Sin(a)*.53f);b.Tube([p,p+new Vector3(.12f,.65f+i%3*.20f,0)],[.15f,.10f],i%2==0?cloth:trim,8);}
        }
        else
        {
            b.RoundBox(new(0,.15f,0),new(1.50f,.30f,1.0f),.06f,rock);
            if(region.Climate==IslandClimate.Shelf)
            {
                for(int i=0;i<4;i++){var p=new Vector3((i-1.5f)*.30f,.18f,0);b.Tube([p,p+Vector3.Up*(1.04f-.17f*i)],.097f,trim);}
                b.Sphere(new(.09f,.40f,.24f),new(.69f,.41f,.48f),new("dae3dc"));
            }
            else
            {
                foreach(int s in new[]{-1,1})b.Tube([new(s*.51f,.29f,0),new(s*.51f,1.29f,0)],.11f,trim,8);
                b.RoundBox(new(0,1.33f,0),new(1.47f,.19f,.48f),.032f,rock);
                b.Polygon([new(-.79f,1.42f,.23f),new(0,1.85f,.23f),new(.79f,1.42f,.23f)],cloth,Vector3.Back);
                if(region.Climate==IslandClimate.Stars)b.Crystal(new(0,1.09f,0),new(.18f,.32f,.18f),trim);
            }
        }
        var art=ShoreSculpture.Bake(b);art.RotationDegrees=new(0,variant%2==0?-12:16,0);return art;
    }
    static Node3D Station(LandingRegion region,LandingJob job)
    {
        if(job==LandingJob.Escort)return Tarp(new(region.Cloth));
        if(job is LandingJob.Capstans or LandingJob.Nets)return ShoreSculpture.WindingPost();
        if(job==LandingJob.Mould)return Workshop(region,0);
        var b=new ActorGeometry();
        for(int i=0;i<3;i++)
        {
            var p=new Vector3((i-1)*.37f,.20f+(i%2)*.06f,0);
            b.RoundBox(p,new(.34f,.38f,.45f),.03f,new(region.Cloth));
            b.RoundBox(p+Vector3.Back*.23f,new(.22f,.16f,.02f),.005f,Ivory);
        }
        return ShoreSculpture.Bake(b);
    }
}
