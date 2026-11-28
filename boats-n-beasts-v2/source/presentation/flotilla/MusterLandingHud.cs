using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

internal partial class MusterLandingHud:Control
{
    public MusterLanding Run=null!;
    Font font=null!;
    static readonly Color Ink=new("142d3af0"),Paper=new("ffebc5"),Gold=new("efca83"),Teal=new("91e6c9"),Rose=new("ef805f");
    public override void _Ready(){font=ThemeDB.FallbackFont;MouseFilter=MouseFilterEnum.Ignore;}
    Vector2 Project(N2 pos,float height=0)=>Run.Stage.Lens.UnprojectPosition(MusterLandingArt.At(pos,height));
    void Box(Rect2 box){DrawRect(box,Ink);DrawLine(box.Position,box.Position+new Vector2(box.Size.X,0),Gold,1.3f);}
    void Text(Vector2 p,string s,int size,Color c,float width=-1)=>DrawString(font,p,s,HorizontalAlignment.Left,width,size,c);
    void Beacon(N2 at,string s,Color dye,float height=.34f)
    {
        Vector2 screen=Project(at,height);float width=font.GetStringSize(s,fontSize:15).X+13;var rect=new Rect2(screen-new Vector2(width/2,19),new(width,24));
        if(rect.Position.X<3||rect.End.X>Size.X-4||rect.Position.Y<118||rect.End.Y>Size.Y-90)return;
        Box(rect);Text(rect.Position+new Vector2(6,18),s,15,dye);
    }
    public override void _Draw()
    {
        var y=Run.Muster;float w=Size.X,h=Size.Y;
        if(Run.MapOpen)
        {
            DrawRect(new(0,0,w,h),new("102b36f5"));Text(new(w*.09f,h*.12f),y.Order.Title,31,Paper);
            Text(new(w*.09f,h*.18f),$"{y.DistrictName}  ·  {y.District+1} / {y.Districts}",20,Gold);
            if(y.Phase==MusterPhase.Tideway)PilotBoard(y,new(w*.08f,h*.22f,w*.46f,h*.60f));else Map(y,new(w*.08f,h*.23f,w*.52f,h*.55f),true);float x=w*.65f;
            Text(new(x,h*.30f),"Skippers’ roll",21,Gold);
            for(int i=0;i<3;i++){var b=y.Boats[i];Text(new(x,h*(.39f+i*.115f)),b.Name,18,MusterLandingArt.Flags[i]);Text(new(x,h*(.43f+i*.115f)),$"{b.Skipper} · {b.Role} · hull {b.Hull}/8{(y.Carrier==i?" · cargo":"")}",16,Paper);}
            DrawMultilineString(font,new(w*.09f,h*.84f),y.Order.Objective,HorizontalAlignment.Left,w*.84f,15,2,Paper);
            Text(new(w*.09f,h*.94f),"M   Back to the slip",18,Teal);return;
        }
        foreach(var a in y.Attacks)Warning(a,y.BoatWarnings.ContainsKey(a));
        Circle(y.Player,.34f,Teal,2.8f);foreach(var b in y.Boats.Where(b=>b.Hull>0&&!b.Through))Circle(b.Worker,.26f,MusterLandingArt.Flags[b.Index],2f);
        if(y.EventTime>0)DrawLine(Project(y.Mate,.5f),Project(y.LineEnd,.38f),Paper,2.2f);
        if(y.Flash>.18f&&y.Foes.Count>0)DrawLine(Project(y.Gunner,.56f),Project(y.LineEnd,.64f),Gold,2.4f);
        if(y.Swing>0){float angle=MathF.Atan2(y.Heading.Y,y.Heading.X);var pts=Enumerable.Range(0,19).Select(i=>Project(y.Player+new N2(MathF.Cos(angle-1.0f+i/9f),MathF.Sin(angle-1.0f+i/9f))*.89f,.25f)).ToArray();DrawPolyline(pts,Paper,2.7f,true);}
        var goals=y.Goals().ToArray();var nearest=goals.OrderBy(m=>N2.DistanceSquared(y.Player,m.At)).ToArray();
        if(y.Phase==MusterPhase.Rally)
        {
            var next=y.Boats.Where(b=>b.Role==MusterRole.Unposted&&b.Hull>0).MinBy(b=>N2.DistanceSquared(y.Player,y.Officer(b.Index)));
            foreach(var b in y.Boats.Where(b=>b.Hull>0)){Beacon(y.Officer(b.Index),b.Skipper+" · "+b.Name,MusterLandingArt.Flags[b.Index],1.06f);if(b==next)Circle(y.Officer(b.Index),.48f,Gold,3);}

        }
        else if(y.Phase==MusterPhase.Guard)
        {
            foreach(var f in y.Foes){var p=Project(f.Position,f.Kind==YardBeast.Guardian?1.95f:1.18f);DrawRect(new(p.X-22,p.Y,44,5),Ink);DrawRect(new(p.X-22,p.Y,44f*f.Health/f.Maximum,5),Rose);if(f.Kind==YardBeast.Guardian)Beacon(f.Position,y.Order.Boss,Rose,2.13f);}
            foreach(var mark in y.ReleaseMarks())Beacon(mark.At,mark.Label,Gold,.56f);
            foreach(var a in y.BoatWarnings)Beacon(a.Key.Origin,$"Protect {a.Value.Name}",Gold,.58f);
        }
        else foreach(var m in goals){if(N2.DistanceSquared(m.At,y.Player)<30)Beacon(m.At,m.Label,Gold,N2.DistanceSquared(m.At,y.Player)<.79f?1.24f:.35f);}
        if(y.Phase is MusterPhase.Work or MusterPhase.Consign)foreach(var f in y.Foes){var p=Project(f.Position,1.20f);DrawRect(new(p.X-17,p.Y,34,4),Ink);DrawRect(new(p.X-17,p.Y,34f*f.Health/f.Maximum,4),Rose);}
        if(y.Team is {Role:MusterRole.Fortify,Step:2} frm){Circle(y.BraceSeat(frm),.45f,Gold,3);Beacon(y.BraceSeat(frm),"Brass shoe",Teal,.06f);}
        Box(new(16,14,Math.Min(w*.61f,782),94));Text(new(31,39),$"{y.Order.Region.ToUpperInvariant()}   ·   {y.DistrictName.ToUpperInvariant()}   {y.District+1}/{y.Districts}",15,Gold);
        Text(new(31,65),y.Order.Title,21,Paper,w*.56f);Text(new(31,90),y.Objective,16,Teal,w*.57f);
        float right=w-239;Box(new(right,14,222,152));Text(new(right+12,37),"Convoy roll",17,Gold);
        for(int i=0;i<3;i++){var b=y.Boats[i];Text(new(right+12,63+34*i),b.Name+(y.Carrier==i?"  ◆":""),16,MusterLandingArt.Flags[i]);Text(new(right+12,79+34*i),$"{b.Hull}/8  ·  {(b.Hull<=0?"grounded":b.Through?"through":b.Ready?"ready":b.Role.ToString())}   ·   {b.People} aboard",13,Paper);}
        if(y.Phase==MusterPhase.Tideway)PilotBoard(y,new(w-342,179,325,348));else Map(y,new(w-202,182,185,133),false);
        if(nearest.Length>0&&N2.DistanceSquared(nearest[0].At,y.Player)>12)
        {
            var d=nearest[0].At-y.Player;string distance=$"{d.Length():0} m";var pos=Project(y.Plan.Waypoint(y.Player,nearest[0].At));var start=Project(y.Player);
            if(start.DistanceSquaredTo(pos)>10){var dir=(pos-start).Normalized();var side=new Vector2(-dir.Y,dir.X);var arrow=start+dir*48;DrawColoredPolygon([arrow+dir*11,arrow-dir*4+side*6,arrow-dir*4-side*6],Gold);Text(arrow+side*9,distance,13,Paper);}
        }
        if(y.LineTime>0)
        {
            float width=Math.Min(w*.77f,font.GetStringSize(y.Line,fontSize:16).X+28);
            float height=font.GetMultilineStringSize(y.Line,HorizontalAlignment.Center,width-22,16).Y+16;var rect=new Rect2((w-width)/2,h-77-height,width,height);Box(rect);
            DrawMultilineString(font,rect.Position+new Vector2(11,21),y.Line,HorizontalAlignment.Center,width-22,16,-1,Paper);
        }
        Box(new(16,h-66,w-32,51));Text(new(29,h-46),$"Vitality {y.Health}/{y.Maximum}     Silver {Run.CarriedSilver+y.Silver}     Rescue packs {y.Spares}     Hulls {y.Alive}/3",15,Teal);
        string controls=y.Phase==MusterPhase.Rally?"WASD  Move    With a skipper   1  Salvage     2  Escort     3  Fortify        M  Chart":y.Team is {Role:MusterRole.Salvage,Step:4}?"At the crew flag    1  Patch this hull    2  Pack two rescue kits    3  Sell the iron and keep the fittings":"WASD  Move    J  Cut / drive    K  Hook    L  Vara    Space  Dodge    E  Work / board    1  Rescue pack    M  Chart";
        Text(new(29,h-23),controls,15,Paper);
        if(y.Lost){DrawRect(new(0,0,w,h),new("132432d8"));DrawString(font,new(0,h*.46f),"The muster breaks",HorizontalAlignment.Center,w,34,Paper);DrawString(font,new(0,h*.46f+52),$"E   Return with {Run.CarriedSilver+y.Silver} silver",HorizontalAlignment.Center,w,21,Gold);}
    }
    void Map(ConvoyLanding y,Rect2 box,bool full)
    {
        if(!full)Box(box);
        var bounds=y.Plan.Patches.SelectMany(p=>p.Rim).ToArray();float minX=bounds.Min(p=>p.X),maxX=bounds.Max(p=>p.X),minY=bounds.Min(p=>p.Y),maxY=bounds.Max(p=>p.Y);
        var size=box.Size-new Vector2(20,18);float scale=Math.Min(size.X/(maxX-minX),size.Y/(maxY-minY));
        Vector2 P(N2 v)=>box.GetCenter()+new Vector2(v.X-(minX+maxX)*.5f,v.Y-(minY+maxY)*.5f)*scale;
        foreach(var span in y.Plan.Passages)DrawLine(P(span.From),P(span.To),new("b7a987"),full?6:2);
        foreach(var island in y.Plan.Patches)DrawColoredPolygon(island.Rim.Select(P).ToArray(),new("586d68"));
        for(int i=0;i<3;i++)DrawCircle(P(y.Station(i)),full?6:3,MusterLandingArt.Flags[i]);
        foreach(var g in y.Goals())DrawArc(P(g.At),full?7:4,0,Mathf.Tau,15,Gold,1.5f,true);
        if(full)for(int i=0;i<3;i++)Text(P(y.Station(i))+new Vector2(8,0),y.Boats[i].Name,14,Paper);
        DrawCircle(P(y.Player),full?6:3.5f,Teal);
    }
    void PilotBoard(ConvoyLanding y,Rect2 box)
    {
        var chart=y.ChannelBoard!;Box(box);float x=box.Position.X+16,top=box.Position.Y+49,width=box.Size.X-32,height=box.Size.Y-129;
        Text(box.Position+new Vector2(14,26),"Tide pilot  ·  "+(y.Order.Articles?.Signal??"three lights"),17,Gold,box.Size.X-26);
        float dx=width/5,dy=height/(chart.Reaches+1);
        Vector2 P(float lane,float row)=>new(x+(lane+.5f)*dx,top+(chart.Reaches-row+.5f)*dy);
        for(int row=0;row<=chart.Reaches;row++)for(int lane=0;lane<5;lane++)
        {
            var pos=P(lane,row);var kind=chart.Water[lane,row];var rect=new Rect2(pos-new Vector2(dx*.46f,dy*.43f),new(dx*.92f,dy*.86f));
            DrawRect(rect,kind==TideCell.Bar?new("786b69"):kind==TideCell.Battery?new("865551"):new("3d666d"));
            string mark=kind switch{TideCell.Bar=>"×",TideCell.Battery=>"!",TideCell.Bales=>"+",TideCell.Lifeline=>"○",TideCell.Eddy=>"~",TideCell.Bond=>"§",TideCell.Lantern=>"*",TideCell.Workshop=>"⚒",_=>""};
            if(mark!="")DrawString(font,new(rect.Position.X,pos.Y+5),mark,HorizontalAlignment.Center,rect.Size.X,16,Paper);
        }
        foreach(var b in y.Boats.Where(b=>b.Hull>0))
        {
            int i=b.Index;var p=P(chart.Lane[i],chart.Row[i]);var c=MusterLandingArt.Flags[i];
            if(!chart.Home(i))
            {
                var dest=P(Math.Clamp(chart.Aimed(i),-.37f,4.37f),chart.Row[i]+1);
                DrawDashedLine(p,dest,c,2.1f,4);DrawArc(dest,5,0,Mathf.Tau,12,c,2);
            }
            DrawColoredPolygon([p+new Vector2(0,-8),p+new Vector2(6,4),p+new Vector2(0,8),p+new Vector2(-6,4)],c);
        }
        float low=top+height+15;Text(new(x,low),"× Bar     ! Battery     + Bales     ○ Swimmer",14,Paper);
        string local=chart.Specialty switch{TideCell.Eddy=>"~ shifts one lane",TideCell.Bond=>"§ costs a fitting or hull",TideCell.Lantern=>"* charts the next bars",_=>"⚒ repairs two hull"};
        Text(new(x,low+18),$"{chart.Landmark} · {local}",13,Gold);
        Text(new(x,low+36),"E at pennant sets helm · K dredges",14,Teal);Text(new(x,low+53),"L at the wheel advances the convoy",14,Teal);
    }
    void Circle(N2 p,float radius,Color color,float stroke){DrawPolyline(Enumerable.Range(0,33).Select(i=>Project(p+new N2(MathF.Cos(i*Mathf.Tau/32),MathF.Sin(i*Mathf.Tau/32))*radius,.04f)).ToArray(),color,stroke,true);}
    void Warning(YardAttack a,bool ship)
    {
        var color=ship?new Color("ecab5b66"):new Color("e76b6866");
        if(a.Shape==AttackShape.Lane){var axis=N2.Normalize(a.Target-a.Origin);var side=new N2(-axis.Y,axis.X)*a.Radius;Vector2[] path=[Project(a.Origin-side),Project(a.Target-side),Project(a.Target+side),Project(a.Origin+side)];DrawColoredPolygon(path,color);DrawPolyline([..path,path[0]],Paper,1.8f,true);return;}
        float inner=a.Shape==AttackShape.Ring?a.Inner:.009f,begin=0,span=Mathf.Tau;
        if(a.Shape==AttackShape.Fan){var h=a.Target-a.Origin;span=2*MathF.Acos(a.Inner);begin=MathF.Atan2(h.Y,h.X)-span/2;}
        for(int i=0;i<30;i++){float t=begin+span*i/30,e=begin+span*(i+1)/30;N2 d=new(MathF.Cos(t),MathF.Sin(t)),n=new(MathF.Cos(e),MathF.Sin(e));DrawColoredPolygon([Project(a.Origin+d*inner),Project(a.Origin+d*a.Radius),Project(a.Origin+n*a.Radius),Project(a.Origin+n*inner)],color);}
        var edge=Enumerable.Range(0,31).Select(i=>Project(a.Origin+new N2(MathF.Cos(begin+span*i/30),MathF.Sin(begin+span*i/30))*a.Radius)).ToArray();DrawPolyline(edge,ship?Gold:Paper,2,true);
        if(a.Shape==AttackShape.Ring)Circle(a.Origin,inner,Paper,1.5f);
    }
}
