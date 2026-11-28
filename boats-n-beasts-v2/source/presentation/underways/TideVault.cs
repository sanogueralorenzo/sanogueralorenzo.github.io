using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

internal static class TideVault
{
    public static MeshInstance3D Shell(LandingRegion region,int seed,int depth)
    {
        var rng=new Random(seed);var g=new ActorGeometry();Color cliff=new(region.Rock),rim=new(region.Trim),cloth=new(region.Cloth);
        var violet=cliff.Lerp(new Color("49405d"),.55f);var limestone=cliff.Lerp(rim,.31f);
        for(int side=-1;side<=1;side+=2)
        {
            var layers=new Vector3[5,25];
            for(int j=0;j<25;j++)
            {
                float z=-5.0f+j*.43f;
                float grain=.27f*MathF.Sin(.58f*j+depth)+.13f*MathF.Cos(.99f*j+side);
                float x=4.94f+grain+.12f*rng.NextSingle();
                float height=.21f+rng.NextSingle()*.16f+.48f*(1+MathF.Cos(.36f*j+side+depth));
                layers[0,j]=new(side*x,.018f,z);
                layers[1,j]=new(side*(x+.13f),height*.21f,z);
                layers[2,j]=new(side*(x+.36f),height*.74f,z);
                layers[3,j]=new(side*(x+.56f),height,z);
                layers[4,j]=new(side*(x+1.58f),height*.78f,z+.08f);
            }
            for(int j=0;j<24;j++)
            {
                if(j%17 is 10 or 11)continue;
                for(int k=0;k<4;k++)
                {
                    var a=layers[k,j];var b=layers[k,j+1];var c=layers[k+1,j+1];var d=layers[k+1,j];
                    var tone=k switch{0=>cliff.Lerp(new Color("84a99e"),.46f),1=>violet,2=>limestone.Darkened(.17f),_=>cliff};
                    g.Polygon([a,b,c,d],tone.Lightened(.047f*rng.NextSingle()),k<3?new(-side,.42f,0):Vector3.Up);
                    if(k!=3||j%3==1)continue;
                    for(int fleck=0;fleck<3;fleck++)
                    {
                        var p=a.Lerp(b,.26f+.15f*fleck)+Vector3.Up*.012f;
                        var t=p.Lerp(d,.26f)+new Vector3(0,0,-.06f);
                        g.Polygon([p,t,t+new Vector3(0,.004f,.019f)],limestone.Darkened(.22f),Vector3.Up);
                    }
                }
                if(j%5!=0)continue;
                var footing=layers[3,j]+new Vector3(side*.25f,.01f,0);
                g.Sphere(footing,new(.23f,.13f,.31f),cliff.Lightened(.11f),7,4);
                for(int k=0;k<3;k++){var p=footing+new Vector3(side*.09f,0,k*.081f);g.Polygon([p,p+new Vector3(.15f,.20f+k*.06f,-.09f),p+new Vector3(.035f,.006f,.035f)],cloth.Lerp(limestone,.35f),Vector3.Up);}
            }
            var post=new Vector3(side*4.47f,.41f,-2.75f);var knee=post+new Vector3(side*.31f,1.40f,-.18f);
            g.Tube([post,knee,knee+new Vector3(-side*.47f,.53f,-.18f)],[.17f,.22f,.16f],limestone,7);
            g.Tube([knee+new Vector3(-.27f,.05f,0),knee+new Vector3(.27f,.05f,0)],.094f,cloth,7);
        }
        for(int j=0;j<9;j++)
        {
            float x=-4.76f+1.19f*j;float z=-4.89f-.47f*rng.NextSingle();float h=.48f+rng.NextSingle()*.73f;
            g.Sphere(new(x,.14f,z),new(1.03f,h,1.12f),violet.Lerp(cliff,rng.NextSingle()*.7f),7,4);
        }
        for(int arch=0;arch<3;arch++)
        {
            float x=-3.10f+arch*3.12f,z=-3.97f-.11f*(depth%3);Color tint=arch==1?limestone:cliff.Lightened(.11f);
            var foot=new Vector3(x,.04f,z);float r=.93f;
            for(int k=0;k<10;k++)
            {
                float a=k*Mathf.Pi/10,b=(k+1)*Mathf.Pi/10;Vector3 At(float angle,float rad)=>foot+new Vector3(MathF.Cos(angle)*rad,.51f+MathF.Sin(angle)*rad,0);
                g.Tube([At(a,r),At(b,r)],[.16f,.17f],tint.Lightened(.06f*(k%3)),5);
            }
            for(int k=-1;k<=1;k+=2){g.RoundBox(foot+new Vector3(k*r,.29f,0),new(.31f,.58f,.44f),.055f,tint);g.RoundBox(foot+new Vector3(k*r,.56f,0),new(.39f,.090f,.48f),.019f,limestone);}
            g.Tube([foot+new Vector3(-.12f,.03f,0),foot+new Vector3(-.12f,.91f,0),foot+new Vector3(.38f,1.04f,0)],.055f,cloth,7);
        }
        return ShoreSculpture.Bake(g);
    }
}
