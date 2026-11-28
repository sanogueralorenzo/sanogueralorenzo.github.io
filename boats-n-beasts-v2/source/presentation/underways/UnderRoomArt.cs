using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;

namespace BoatsNBeasts;
internal sealed class UnderRoomArt
{
    public const float Level=.45f;
    public readonly Node3D Root=new();
    readonly List<(UnderDoor Door,Node3D Grille)> doors=[];
    readonly List<(int I,Node3D Prop)> objects=[];
    readonly List<Node3D> scraps=[];
    Node3D? passenger,crate;readonly ExchangeArt? exchange;
    static readonly Color Iron=new("494859"),Brass=new("dbaa68"),Paper=new("eaddb8"),Wood=new("886949");
    public static Vector3 Place(N2 p,float y=0)=>new(p.X,Level+y,p.Y);
    public UnderRoomArt(UnderwayRun run)
    {
        var r=run.Room;var region=LandingRegion.From(run.Order.Region);Color ground=new(region.Ground),rock=new(region.Rock),cloth=new(region.Cloth),trim=new(region.Trim);
        Root.AddChild(TideVault.Shell(region,r.Seed,run.Depth));
        var rng=new Random(r.Seed);var b=new ActorGeometry();
        Color paving=ground.Lerp(rock,.33f);
        b.RoundBox(new(0,.14f,0),new(9.28f,.58f,6.90f),.105f,rock);
        for(int row=0;row<9;row++)for(int col=0;col<12;col++)
        {
            float x=-4.27f+col*.78f,z=-3.06f+row*.76f;
            var c=paving.Lightened(rng.NextSingle()*.13f);b.RoundBox(new(x,Level-.018f,z),new(.762f,.052f,.741f),.025f,c);
            if(rng.Next(3)!=0)continue;
            for(int k=0;k<3;k++)
            {
                var p=new Vector3(x-.13f+k*.051f,Level+.014f,z+.101f+k*.023f);
                b.Polygon([p,p+new Vector3(.14f+.03f*k,0,-.072f),p+new Vector3(.027f,0,.008f)],c.Darkened(.12f),Vector3.Up);
            }
        }
        var exits=run.Floor.Exits(run.Here).ToArray();
        foreach(var d in exits)
        {
            var site=run.Floor.Threshold(run.Here,d);var unit=N2.Normalize(site);var side=new N2(-unit.Y,unit.X);var frame=new ActorGeometry();var gate=new ActorGeometry();
            Vector3 P(float x,float y,float z)=>Place(site+side*x+unit*z,y);
            foreach(float s in new[]{-.61f,.61f})
            {
                frame.RoundBox(P(s,.40f,.10f),new(.19f,.80f,.19f),.036f,rock);
                frame.Tube([P(s,.73f,.10f),P(s,1.11f,.10f)],[.12f,.085f],Brass,7);
                frame.Crystal(P(s,1.15f,.10f),new(.084f,.16f,.084f),d.Gate==UnderGate.Seal?new("97c2cb"):trim);
            }
            for(int k=-2;k<=2;k++)gate.Tube([P(k*.218f,.03f,.11f),P(k*.218f,.83f,.11f)],.042f,Iron,7);
            gate.Tube([P(-.58f,.68f,.11f),P(.58f,.68f,.11f)],.065f,Brass,7);
            Root.AddChild(ShoreSculpture.Bake(frame));var grille=ShoreSculpture.Bake(gate);Root.AddChild(grille);doors.Add((d,grille));
        }
        for(int wall=0;wall<4;wall++)
        {
            bool sideWall=wall<2;float sign=wall%2==0?-1:1;int n=sideWall?10:13;
            for(int j=0;j<n;j++)
            {
                float lane=(j-(n-1)*.5f)*.70f;N2 pos=sideWall?new(sign*4.56f,lane):new(lane,sign*3.39f);
                if(exits.Any(d=>N2.DistanceSquared(run.Floor.Threshold(run.Here,d),pos)<.79f))continue;
                bool front=!sideWall&&sign>0;float height=front?.19f:sideWall?.34f+.08f*(j%3):.85f+.10f*(j%3);
                b.RoundBox(Place(pos,height*.5f),new(sideWall?.26f:.65f,height,sideWall?.64f:.26f),.042f,rock.Lightened(.10f*(j%3)));
                b.RoundBox(Place(pos,height+.015f),new(sideWall?.30f:.67f,.05f,sideWall?.66f:.30f),.014f,rock.Lerp(trim,.27f));
                if(!front&&j%4==1)
                {
                    b.Tube([Place(pos,height),Place(pos,height+.37f)],.048f,Wood,7);
                    b.Crystal(Place(pos,height+.40f),new(.11f,.17f,.11f),Paper);
                    b.RoundBox(Place(pos,height+.60f),new(.25f,.044f,.23f),.009f,Brass);
                }
            }
        }
        foreach(float sign in new[]{-1f,1f})
        {
            var plinth=new N2(sign*3.33f,-2.50f);
            b.RoundBox(Place(plinth,.09f),new(.93f,.18f,.67f),.049f,rock);
            if(region.Climate>=IslandClimate.Saltstep){var art=TideWorkshop.Make(region,r.Id);art.Scale=Vector3.One*.55f;Add(art,plinth,.18f);}
            else{b.Tube([Place(plinth,.14f),Place(plinth,.66f)],[.19f,.11f],cloth,7);b.Ring(Place(plinth,.67f),.14f,.035f,Brass);b.Crystal(Place(plinth,.83f),new(.16f,.23f,.14f),trim);}
        }
        Root.AddChild(ShoreSculpture.Bake(b));
        if(r.Trial>=UnderTrial.Drain)exchange=new(Root,run);
        switch(r.Trial)
        {
            case UnderTrial.Mouth:Add(YardWorkProps.Item("ledger"),run.WardDesk);Add(ActorArt3D.ShoreSkiff(),new(-3.18f,1.68f),-.12f).Scale=Vector3.One*.68f;break;
            case UnderTrial.Stores:case UnderTrial.Camp:Add(YardWorkProps.Item("sealed"),run.FittingBench);Add(YardWorkProps.Item("ledger"),run.WardDesk);break;
            case UnderTrial.Keeper:Add(YardWorkProps.Item("ledger"),run.WardDesk);Add(ShoreSculpture.WindingPost(),run.Winch);for(int i=0;i<2;i++)Add(YardWorkProps.Item("valve"),run.Pad(i));break;
            case UnderTrial.Mirrors:
                for(int i=0;i<3;i++)
                {
                    var glass=new ActorGeometry();glass.RoundBox(new(0,.31f,0),new(.66f,.48f,.066f),.033f,Brass);
                    glass.RoundBox(new(0,.34f,-.041f),new(.56f,.37f,.032f),.015f,new("90c9ce"));glass.RoundBox(new(0,.34f,.041f),new(.56f,.37f,.032f),.015f,new("90c9ce"));
                    objects.Add((i,Add(ShoreSculpture.Bake(glass),r.Board!.GlassAt(i))));
                }
                Add(YardWorkProps.Item("valve"),r.Board!.Source);Add(YardWorkProps.Item("stamp"),r.Board.Receiver);break;
            case UnderTrial.Freight:
                var deck=new ActorGeometry();foreach(var tile in r.Board!.Walls)deck.RoundBox(Place(tile,.19f),new(.61f,.37f,.61f),.053f,Iron);
                foreach(var tile in r.Board.Sockets){deck.RoundBox(Place(r.Board.At(tile),.028f),new(.73f,.055f,.73f),.038f,Brass);}
                Root.AddChild(ShoreSculpture.Bake(deck));
                for(int i=0;i<2;i++)objects.Add((i,Add(YardWorkProps.Item("sealed"),r.Board.At(r.Board.Blocks[i]))));Add(YardWorkProps.Item("ledger"),run.WardDesk);break;
            case UnderTrial.Chart:for(int i=0;i<3;i++)Add(YardWorkProps.Item("stamp"),run.Pad(i));Add(YardWorkProps.Item("ledger"),run.Reader);break;
            case UnderTrial.Capstan:for(int i=0;i<3;i++)Add(YardWorkProps.Item("valve"),run.Pad(i));Add(ShoreSculpture.WindingPost(),run.Rotary);for(int i=0;i<2;i++)objects.Add((i,Add(YardWorkProps.Item("weight"),run.LoadAt(i))));break;
            case UnderTrial.Rescue:passenger=Add(ActorArt3D.LandingParty(2),r.Escort);for(int i=0;i<2;i++)Add(YardWorkProps.Item("flag"),run.Pad(r.Code[i+1]));Add(YardWorkProps.Item("net"),run.Winch);break;
            case UnderTrial.Cradle:crate=Add(YardWorkProps.Item("sealed"),r.Cargo);Add(YardWorkProps.Item("mould"),run.Winch);for(int i=0;i<3;i++)Add(YardWorkProps.Item("valve"),run.Pad(i));break;
        }
    }
    Node3D Add(Node3D model,N2 p,float height=0){model.Position=Place(p,height);Root.AddChild(model);return model;}
    public void Sync(UnderwayRun run)
    {
        exchange?.Sync(run);var r=run.Room;foreach(var(d,gate)in doors)gate.Visible=!d.Opened&&d.Gate!=UnderGate.Open&&!run.CanOpen(d);
        foreach(var(i,part)in objects)
        {
            if(r.Trial==UnderTrial.Mirrors)part.Rotation=new(0,r.Board!.SlantsForward(i)?Mathf.Pi*.25f:-Mathf.Pi*.25f,0);
            if(r.Trial==UnderTrial.Freight)part.Position=Place(r.Board!.At(r.Board.Blocks[i]));
            if(r.Trial==UnderTrial.Capstan){part.Visible=run.LoadLive;part.Position=Place(run.LoadAt(i),.085f);}
        }
        if(passenger!=null){passenger.Position=Place(r.Escort);passenger.Visible=!r.Cleared;}
        if(crate!=null)crate.Position=Place(r.Cargo, .02f);
        while(scraps.Count<r.Drops.Count){var part=YardWorkProps.Item("weight");part.Scale=Vector3.One*.48f;Add(part,N2.Zero);scraps.Add(part);}
        while(scraps.Count>r.Drops.Count){scraps[^1].QueueFree();scraps.RemoveAt(scraps.Count-1);}
        for(int i=0;i<scraps.Count;i++)scraps[i].Position=Place(r.Drops[i],.05f+.035f*MathF.Sin(run.Clock*3+i));
    }
}
