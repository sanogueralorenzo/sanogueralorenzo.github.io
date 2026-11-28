using Godot;

namespace BoatsNBeasts;

internal static class BellPlateArt
{
    static readonly Color Iron=new("51445c"), Edge=new("827381"), Bronze=new("ab7046"), Brass=new("e9ae60"), Bright=new("f5cc86"), Verdigris=new("4b978b"), Deep=new("316f70"), Seal=new("f4c89a");
    static Vector3[] Rim(float width,float depth,float y,int n=20)=>Enumerable.Range(0,n).Select(i=>new Vector3(MathF.Cos(i*Mathf.Tau/n)*width,y,MathF.Sin(i*Mathf.Tau/n)*depth)).ToArray();
    public static MeshInstance3D Build()
    {
        var b=new ActorGeometry();var random=new Random(241);
        foreach(int side in new[]{-1,1})
        {
            var hip=new Vector3(side*.43f,.65f,.01f);var knee=new Vector3(side*.52f,.36f,-.055f);
            b.Tube([hip,knee,knee+new Vector3(side*.03f,-.22f,.035f)],[.21f,.235f,.17f],Iron,7);
            b.RoundBox(knee+new Vector3(0,-.19f,-.095f),new(.44f,.27f,.56f),.057f,Edge.Darkened(.18f));
            foreach(float x in new[]{-.10f,.10f})b.RoundBox(knee+new Vector3(x,-.23f,-.36f),new(.17f,.15f,.15f),.025f,Iron);
        }
        b.Loft([Rim(.79f,.73f,.51f),Rim(.86f,.79f,.60f),Rim(.84f,.77f,.685f),Rim(.78f,.72f,.73f),Rim(.62f,.55f,1.34f),Rim(.58f,.52f,1.42f),Rim(.54f,.48f,1.49f)],[Bronze,Brass,Bright,Deep,Verdigris,Brass]);
        b.Polygon(Rim(.54f,.48f,1.49f),Bronze,Vector3.Up);
        Vector3 Metal(float a,float y,float lift=0)
        {float t=Mathf.Clamp((y-.73f)/.61f,0,1);return new(MathF.Cos(a)*(Mathf.Lerp(.78f,.62f,t)+lift),y,MathF.Sin(a)*(Mathf.Lerp(.72f,.55f,t)+lift));}
        for(int i=0;i<20;i++)
        {
            float a=i*Mathf.Tau/20;
            b.Sphere(new(.844f*MathF.Cos(a),.638f,.781f*MathF.Sin(a)),new(.039f,.035f,.04f),i%2==0?Bright:Bronze,8,4);
            for(int j=0;j<5;j++)
            {
                float angle=a+random.NextSingle()*.20f;float y=.76f+random.NextSingle()*.52f;float len=.045f+random.NextSingle()*.065f;
                b.Polygon([Metal(angle,y,.011f),Metal(angle+.045f,y+.012f,.012f),Metal(angle+.10f,y+len,.013f),Metal(angle+.075f,y+len*.85f,.012f)],j%3==0?Bronze:Verdigris,Metal(angle,0) with {Y=0});
            }
            if(i%5==0)
            {
                float angle=a+.11f;
                b.Tube([Metal(angle,1.19f,.023f),Metal(angle,1.02f,.028f),Metal(angle,.94f,.032f)],.021f,Seal,6);
                b.Tube([Metal(angle-.14f,1.17f,.021f),Metal(angle-.11f,1.09f,.028f),Metal(angle,1.02f,.028f),Metal(angle+.11f,1.09f,.028f),Metal(angle+.14f,1.17f,.021f)],.018f,Seal,6);
            }
        }
        b.Loft([Rim(.41f,.37f,1.42f,10),Rim(.46f,.40f,1.62f,10),Rim(.41f,.34f,1.78f,10),Rim(.27f,.23f,1.87f,10)],[Iron,Edge,Iron]);
        b.Polygon(Rim(.27f,.23f,1.87f,10),Bronze,Vector3.Up);
        b.RoundBox(new(0,1.61f,-.329f),new(.59f,.19f,.15f),.05f,Iron.Darkened(.34f));
        foreach(int side in new[]{-1,1})
        {
            b.Tube([new(side*.29f,1.72f,-.29f),new(side*.21f,1.70f,-.393f),new(side*.06f,1.65f,-.418f)],[.078f,.068f,.056f],Edge,6);
            b.Tube([new(side*.235f,1.62f,-.414f),new(side*.08f,1.588f,-.421f)],[.028f,.018f],new("ffac5f"),6);
            var p=new Vector3(side*.60f,1.42f,.015f);
            b.Sphere(p,new(.34f,.34f,.32f),Bronze,8,5);b.Sphere(p+new Vector3(side*.03f,.11f,-.02f),new(.33f,.24f,.34f),Brass,9,5);
            b.Tube([p+Vector3.Forward*.30f,p+Vector3.Forward*.36f],[.17f,.12f],Bronze,10);
            b.Sphere(p+Vector3.Forward*.38f,new(.061f,.061f,.027f),Bright,8,4);
        }
        b.Sphere(new(-.79f,1.08f,.03f),new(.255f,.27f,.25f),Edge,7,4);
        b.Tube([new(-.70f,1.37f,0),new(-.92f,1.03f,.03f),new(-1.07f,.73f,-.22f)],[.17f,.21f,.19f],Iron,7);
        for(int i=0;i<3;i++)b.RoundBox(new(-.85f-i*.07f,1.11f-i*.11f,-.10f-i*.04f),new(.37f,.14f,.36f),.035f,i%2==0?Edge:Iron);
        b.RoundBox(new(-1.05f,.68f,-.22f),new(.42f,.36f,.45f),.068f,Iron);for(int i=0;i<3;i++)b.RoundBox(new(-1.18f+i*.12f,.64f,-.45f),new(.11f,.17f,.10f),.013f,Edge);
        var ring=Enumerable.Range(0,17).Select(i=>new Vector3(.195f*MathF.Cos(Mathf.Tau*i/16),1.95f+.20f*MathF.Sin(Mathf.Tau*i/16),.02f)).ToArray();
        b.Tube(ring,.067f,Brass,8);b.RoundBox(new(0,1.84f,.02f),new(.41f,.09f,.20f),.029f,Bronze);
        var body=ShoreSculpture.Bake(b);
        var arm=new ActorGeometry();
        arm.Tube([new(0,0,0),new(.20f,-.30f,.11f),new(.32f,-.53f,-.12f)],[.17f,.19f,.15f],Iron,7);
        arm.Sphere(new(.20f,-.27f,.10f),new(.23f,.23f,.23f),Edge,7,4);
        arm.RoundBox(new(.36f,-.52f,-.12f),new(.30f,.26f,.33f),.05f,Iron);
        arm.Tube([new(.28f,-.48f,.02f),new(.62f,-.58f,-.42f),new(.83f,-.63f,-.69f)],[.063f,.079f,.065f],Bronze,8);
        arm.Tube([new(.58f,-.57f,-.37f),new(.64f,-.59f,-.45f)],.099f,Bright,8);
        Vector3 back=new(.78f,-.64f,-.62f),end=back+new Vector3(.29f,-.07f,-.31f);
        arm.Tube([back,back.Lerp(end,.14f),back.Lerp(end,.27f),back.Lerp(end,.77f),back.Lerp(end,.91f),end],[.18f,.244f,.235f,.28f,.30f,.26f],Brass,12);
        arm.Tube([back.Lerp(end,.28f),back.Lerp(end,.73f)],[.239f,.274f],Verdigris,12);
        var pivot=ShoreSculpture.Bake(arm);pivot.Position=new(.62f,1.42f,0);body.AddChild(pivot);
        return body;
    }
}
