using BoatsNBeasts.Core;

using Godot;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    internal static Node3D QuayArch()
    {
        var art=new Sculptor();
        Land(art,1.26f,238,true);
        art.Transform=new Transform3D(Basis.Identity.Scaled(Vector3.One*.82f),new(0,.15f,0));
        AncientArch(art,734);
        art.Transform=Transform3D.Identity;
        for(int i=0;i<5;i++)
        {
            float x=i<2?-1.32f-i*.26f:.78f+(i-2)*.29f;
            art.Boulder(new(x,.22f,.12f+Mathf.Sin(i*2)*.28f),new(.49f,.75f+(i%3)*.20f,.64f),new Color("b9795e").Lightened((i%2)*.12f),(uint)(53+i));
        }
        return art.Finish("TheCrackedGate");
    }
    internal static Node3D FloatingKitchen()
    {
        var a=new Sculptor();
        for(int i=0;i<9;i++)
        {
            float x=(i-4)*.22f;
            a.Tube(new(x,-.03f,-1.35f),new(x,-.03f,1.35f),.14f,.13f,new Color("946444").Lightened(.035f*(i%3)),8);
        }
        for(int i=0;i<9;i++)
            a.RoundedBox(new(0,.12f,(i-4)*.29f),new(1.90f,.12f,.278f),.023f,new Color("c28d61").Lightened((i%3)*.04f));
        AddCottage(a,new(0,.16f,-.27f),.66f,-.09f);
        for(int i=0;i<3;i++)Barrel(a,new(-.63f+i*.43f,.17f,.94f),.26f);
        a.Tube(new(.70f,.15f,.84f),new(.70f,1.47f,.84f),.035f,.026f,new("956241"),6);
        a.Face(new(.70f,1.46f,.84f),new(.70f,1.22f,.84f),new(1.13f,1.38f,.89f),new("d4684e"));
        return a.Finish("TheTravelingKitchen");
    }
    static void MessAwning(Sculptor art)
    {
        Vector3[] posts=[new(-1.49f,.24f,.60f),new(.04f,.24f,.49f),new(.06f,.24f,1.64f),new(-1.50f,.24f,1.76f)];
        Color mast=new("895239"),gold=new("f2bd75");
        foreach(var p in posts)
        {
            art.Tube(p,p+Vector3.Up*1.61f,.033f,.024f,mast,7);
            for(int j=0;j<3;j++)art.Tube(p+Vector3.Up*(1.51f+.031f*j),p+Vector3.Up*(1.532f+.031f*j),.04f,.04f,gold,8);
        }
        Color[] cloth=[new("c95845"),new("d8694d"),new("d35f46"),new("e27550"),new("cf6047")];
        Vector3 Sheet(float u,float v)
        {
            var pt=posts[0].Lerp(posts[1],u).Lerp(posts[3].Lerp(posts[2],u),v);
            pt.Y+=1.61f-.12f*Mathf.Sin(Mathf.Pi*u)-.10f*Mathf.Sin(Mathf.Pi*v)+.04f*Mathf.Sin(u*4f+v*2f);
            return pt;
        }
        for(int i=0;i<5;i++)
            for(int j=0;j<3;j++)
            {
                float u=i/5f,v=j/3f;
                var a=Sheet(u,v);var b=Sheet(u+.20f,v);var c=Sheet(u+.20f,v+1/3f);var d=Sheet(u,v+1/3f);
                art.Face(a,c,b,cloth[i]);art.Face(a,d,c,cloth[i].Lightened(.018f));
                if(j==2)
                {
                    var mid=(c+d)/2-Vector3.Up*.115f;
                    art.Face(d,c,mid,cloth[i].Darkened(.12f));
                    art.Tube(d,mid,.014f,.005f,gold,5);
                }
            }
        for(int i=0;i<3;i++)
        {
            var basePoint=Sheet(.40f+i*.083f,.58f)+Vector3.Up*.014f;
            art.Tube(basePoint,basePoint+new Vector3(-.071f,.013f,-.12f),.016f,.009f,gold,6);
            art.Tube(basePoint,basePoint+new Vector3(.074f,.015f,-.13f),.016f,.009f,gold,6);
        }
    }

    static void Boatyard(Sculptor art)
    {
        Color rock=new("bc7458"),stone=new("e2a575"),wood=new("875637");
        var seed=new SeedRandom(83);
        for(int i=0;i<13;i++)
        {
            float t=i/12f;
            var pt=new Vector3(Mathf.Lerp(-3.65f,2.77f,t),.0f,-1.91f-.57f*Mathf.Sin(t*Mathf.Pi));
            art.Boulder(pt,new(.88f,.80f+.42f*Mathf.Sin(t*Mathf.Pi),.95f),rock.Lightened(.11f*(i%3)),seed.Next());
            art.Boulder(pt+new Vector3(.09f,.32f,.02f),new(.83f,.52f,.77f),stone.Lightened(.06f*(i%2)),seed.Next());
        }
        var frame=art.Transform;
        art.Transform=frame*new Transform3D(Basis.FromEuler(new(0,-.36f,0)).Scaled(Vector3.One*.74f),new(-3.02f,.55f,-2.46f));
        PirateTavern(art);
        art.Transform=frame;
        for(int i=0;i<7;i++)
        {
            float x=-3.55f+i*.57f,z=2.92f+.18f*Mathf.Sin(i*.65f);
            var at=new Vector3(x,.11f,z);
            art.RoundedBox(at,new(.56f,.31f,.38f),.033f,rock.Lightened((i%3)*.085f));
            art.RoundedBox(at+new Vector3(-.04f,.17f,-.06f),new(.55f,.13f,.45f),.027f,stone);
            art.RoundedBox(at+new Vector3(.05f,.02f,.196f),new(.29f,.02f,.012f),.004f,rock.Darkened(.27f));
        }
        for(int j=0;j<4;j++)
        {
            var at=new Vector3(-3.12f+j%2*.31f,.40f+j/2*.25f,.38f);
            art.RoundedBox(at,new(.29f,.24f,.27f),.013f,wood.Lightened(.09f*(j%2)));
            for(int k=-1;k<=1;k+=2)
                art.RoundedBox(at+new Vector3(k*.09f,0,.14f),new(.035f,.25f,.021f),.005f,stone);
        }
        var left=new Vector3(.42f,1.94f,-.53f);var right=new Vector3(2.69f,1.88f,-.66f);
        for(int i=0;i<8;i++)
        {
            Vector3 Line(float t)=>left.Lerp(right,t)-Vector3.Up*.24f*Mathf.Sin(t*Mathf.Pi);
            var a=Line(i/8f);var b=Line((i+1)/8f);
            art.Tube(a,b,.014f,.014f,wood,6);
            var tip=(a+b)/2+new Vector3(.07f,-.27f,.025f);
            art.Face(a,b,tip,i%3==0?new("318479"):new("dc674c"));
        }
        art.Tube(right-Vector3.Up*1.75f,right+Vector3.Up*.07f,.042f,.027f,wood,6);
        art.Tube(left-Vector3.Up*1.46f,left+Vector3.Up*.07f,.042f,.027f,wood,6);
    }
}
