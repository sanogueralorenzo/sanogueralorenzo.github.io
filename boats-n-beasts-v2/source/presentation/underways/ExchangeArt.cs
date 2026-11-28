using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

internal sealed class ExchangeArt
{
    readonly Node3D host;
    readonly List<Node3D> joints=[];

    Node3D? parcel,cover;
    static readonly Color Bronze=new("c79860"),Iron=new("555360"),Blue=new("8fc6c6"),Cream=new("f0d99f"),Brick=new("977b6a");
    public ExchangeArt(Node3D host,UnderwayRun y)
    {
        this.host=host;
        var bed=new ActorGeometry();var r=y.Room;
        if(r.Pipes is {} pipes)
        {
            for(int i=0;i<16;i++)
            {
                var p=DrainageBoard.At(i);bed.RoundBox(UnderRoomArt.Place(p,.036f),new(.94f,.071f,.94f),.046f,Brick);
                var pipe=new ActorGeometry();pipe.Tube([new(0,.070f,0),new(0,.22f,0)],pipes.Bolted[i]?.205f:.153f,i==pipes.Source?Blue:pipes.Outlets.Contains(i)?Cream:Bronze,10);
                for(int d=0;d<4;d++)if((pipes.Joints[i]&(1<<d))!=0)
                {
                    var a=new Vector3(MathF.Sin(d*Mathf.Pi/2),0,-MathF.Cos(d*Mathf.Pi/2));
                    pipe.Tube([new Vector3(0,.143f,0),a*.46f+new Vector3(0,.143f,0)],.09f,Iron,8);
                    pipe.Tube([a*.38f+new Vector3(0,.143f,0),a*.43f+new Vector3(0,.143f,0)],.117f,Bronze,8);
                }
                if(pipes.Bolted[i])pipe.Crystal(new(0,.27f,0),new(.077f,.105f,.077f),i==pipes.Source?Blue:Cream);
                joints.Add(Add(ShoreSculpture.Bake(pipe),p));
            }
            Add(YardWorkProps.Item("valve"),y.SampleDesk);
        }
        if(r.Rail is {} rail)
        {
            for(int from=-1;from<7;from++)
            {
                int[] to=from<0?[0]:[from*2+1,from*2+2];
                foreach(int n in to)
                {
                    var a=rail.At(from);var b=rail.At(n);var axis=N2.Normalize(b-a);var side=new N2(-axis.Y,axis.X)*.074f;
                    foreach(var v in new[]{side,-side})bed.Tube([UnderRoomArt.Place(a+v,.073f),UnderRoomArt.Place(b+v,.073f)],.021f,Iron,6);
                    for(int k=1;k<=3;k++){var p=N2.Lerp(a,b,k*.25f);bed.Tube([UnderRoomArt.Place(p-side*1.53f,.049f),UnderRoomArt.Place(p+side*1.53f,.049f)],.030f,Brick,5);}
                }
            }
            for(int i=0;i<7;i++){var b=new ActorGeometry();b.Ring(new(0,.10f,0),.16f,.035f,Bronze);b.Tube([new(0,.10f,0),new(.15f,.42f,0)],.032f,Iron,7);b.Crystal(new(.15f,.43f,0),new(.08f,.09f,.08f),Cream);joints.Add(Add(ShoreSculpture.Bake(b),rail.At(i)));}
            for(int i=0;i<8;i++){var b=new ActorGeometry();b.RoundBox(new(0,.065f,0),new(.65f,.13f,.57f),.039f,Brick);Add(ShoreSculpture.Bake(b),rail.At(i+7));}
            parcel=Add(YardWorkProps.Item("sealed"),rail.Cart);parcel.Scale=Vector3.One*.76f;
            Add(YardWorkProps.Item("flag"),y.CartBell);
        }
        if(r.Trial==UnderTrial.Dig)
        {
            Add(YardWorkProps.Item("ledger"),y.Notebook);
            for(int i=0;i<3;i++)
            {
                var p=y.Pad(i);for(int j=0;j<4;j++){var q=p+new N2(MathF.Cos(j*1.6f),MathF.Sin(j*1.6f))*.31f;bed.Crystal(UnderRoomArt.Place(q,.09f),new(.19f,.12f,.22f),Brick.Lightened(j*.055f));}
            }
            cover=Add(YardWorkProps.Item("mould"),y.Pad(y.RockIndex));parcel=Add(YardWorkProps.Item("sealed"),y.Pad(y.RockIndex),.12f);
        }
        if(r.Mosaic!=null)
        {
            for(int i=0;i<9;i++)
            {
                var p=TornChart.At(i);bed.RoundBox(UnderRoomArt.Place(p,.035f),new(1.24f,.07f,1.15f),.025f,Iron);
                if(i==0)continue;var plate=new ActorGeometry();plate.RoundBox(new(0,.12f,0),new(1.11f,.15f,1.03f),.045f,Brick.Lightened(i*.025f));
                float x=(i-1)%3-1,z=(i-1)/3-1;
                for(int k=0;k<3;k++)plate.Tube([new(-.51f,.207f,.20f*MathF.Sin(x+z+k)),new(.02f,.207f,.20f*MathF.Sin(x+z+k+.5f)),new(.51f,.207f,.20f*MathF.Sin(x+z+k+1))],.014f,k==0?Cream:Bronze,5);
                joints.Add(Add(ShoreSculpture.Bake(plate),p));
            }
            Add(YardWorkProps.Item("ledger"),y.AssayDesk);
        }
        if(r.Balance is {} scale)
        {
            for(int i=0;i<3;i++)
            {
                var p=scale.At(i);bed.RoundBox(UnderRoomArt.Place(p,.045f),new(.67f,.09f,.64f),.038f,Brick);
                var weight=Add(YardWorkProps.Item("weight"),p);weight.Scale=Vector3.One*(.69f+i*.20f);joints.Add(weight);
            }
            bed.RoundBox(UnderRoomArt.Place(y.AssayDesk,.27f),new(1.97f,.22f,.73f),.055f,Bronze);
            for(int k=-1;k<=1;k+=2)
            {
                var p=y.AssayDesk+new N2(k*.78f,0);bed.Tube([UnderRoomArt.Place(p,.42f),UnderRoomArt.Place(p,.58f)],[.34f,.43f],Iron,12);
            }
            bed.Tube([UnderRoomArt.Place(y.AssayDesk,.41f),UnderRoomArt.Place(y.AssayDesk,.87f)],.065f,Cream,8);
        }
        host.AddChild(ShoreSculpture.Bake(bed));
    }
    Node3D Add(Node3D part,N2 p,float height=0){part.Position=UnderRoomArt.Place(p,height);host.AddChild(part);return part;}
    public void Sync(UnderwayRun y)
    {
        var r=y.Room;
        if(r.Pipes is {} pipes)for(int i=0;i<joints.Count;i++)joints[i].Rotation=new(0,-pipes.Turns[i]*Mathf.Pi/2,0);
        if(r.Rail is {} rail)
        {
            for(int i=0;i<joints.Count;i++)joints[i].Rotation=new(0,rail.Divert[i]?0:Mathf.Pi,0);
            parcel!.Position=UnderRoomArt.Place(rail.Cart,.11f);
        }
        if(r.Trial==UnderTrial.Dig){cover!.Visible=r.Step<3;parcel!.Visible=r.Step==3&&!r.Cleared;}
        if(r.Mosaic is {} torn)for(int i=0;i<9;i++)if(torn.Tiles[i]>0)joints[torn.Tiles[i]-1].Position=UnderRoomArt.Place(TornChart.At(i));
        if(r.Balance is {} scale)for(int i=0;i<joints.Count;i++)
            joints[i].Position=scale.Pan[i]==0?UnderRoomArt.Place(scale.At(i),.07f):UnderRoomArt.Place(y.AssayDesk+new N2(scale.Pan[i]*.78f+(i-1)*.16f,i*.084f),.56f);
    }
}
