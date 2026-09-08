using Godot;
using Further.Core;
using V2=System.Numerics.Vector2;
namespace Further;
public partial class Hud : Control
{
    public Game Game=null!;
    readonly Font font=new SystemFont{FontNames=["Avenir Next","Helvetica Neue"]};
    readonly Font serif=new SystemFont{FontNames=["Georgia"]};
    readonly Color cream=Art.Cream,ink=Art.Ink,gold=Art.Gold;
    Color muted=new("a4bbb7");
    Vector2 dimensions=>GetViewportRect().Size;
    static int FontSize(int size)=>Mathf.RoundToInt(size*1.18f);
    void Text(string text,float x,float y,int size,Color color,bool display=false){size=FontSize(size);var face=display?serif:font;DrawStringOutline(face,new(x,y),text,HorizontalAlignment.Left,-1,size,2,new Color(ink,.40f));DrawString(face,new(x,y),text,HorizontalAlignment.Left,-1,size,color);}
    void Center(string text,float y,int size,Color color,bool display=false){float width=(display?serif:font).GetStringSize(text,HorizontalAlignment.Left,-1,FontSize(size)).X;Text(text,(dimensions.X-width)*.5f,y,size,color,display);}
    void Panel(Rect2 rect,Color color,float radius=12)
    {
        var box=new StyleBoxFlat{BgColor=color,CornerRadiusTopLeft=(int)radius,CornerRadiusTopRight=(int)radius,CornerRadiusBottomLeft=(int)radius,CornerRadiusBottomRight=(int)radius,BorderColor=new Color(gold,.16f),BorderWidthBottom=1,BorderWidthTop=1,BorderWidthLeft=1,BorderWidthRight=1};DrawStyleBox(box,rect);
    }
    public override void _Ready(){MouseFilter=MouseFilterEnum.Ignore;SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);}
    public override void _Draw()
    {
        if(Game.Run==null)return;var r=Game.Run;float w=dimensions.X,h=dimensions.Y;
        if(Game.Title){DrawTitle();return;}
        bool sailing=r.Mode==RunMode.Sailing;
        if(!sailing || r.Health<100)
        {
            float x=w/2-92;DrawRect(new(x,h-43,184,4),new Color(ink,.55f));
            DrawRect(new(x,h-43,184*r.Health/100,4),new("dcb9a0"));
            if(r.Stamina<.98f)DrawRect(new(x,h-34,184*r.Stamina,2),new("94b5a1"));
        }
        DrawCircle(new(w-79,39),4,gold);Text(r.Gold.ToString(),w-64,44,17,cream);
        Text("TAB  ·  chart & crew",w-178,h-24,12,new Color(cream,.65f));
        if(sailing)
        {
            float degrees=Mathf.PosMod(r.Ship.Heading*180/Mathf.Pi,360);
            string bearing=degrees<45||degrees>=315?"N":degrees<135?"E":degrees<225?"S":"W";
            Center(bearing,37,14,cream);DrawLine(new(w/2-35,45),new(w/2+35,45),new Color(cream,.5f),1);
        }
        if(r.Prompt.Length>0)Center(r.Prompt,h-78,16,cream);
        else if(sailing && r.Time<9)Center("W sail  ·  A / D helm",h-78,15,new Color(cream,MathF.Min(1,(float)(9-r.Time))));
        if(r.NoticeTime>0 && !r.Notice.StartsWith("+"))Center(r.Notice,84,15,new Color(cream,MathF.Min(1,r.NoticeTime)));
        DrawCombat();
        if(Game.IsValidation)Text("VALIDATION",24,h-24,10,new Color(cream,.5f));
        if(Game.Chart)
        {
            DrawRect(new(0,0,w,h),new Color(new Color("111f23"),.97f));
            Text("The voyage",70,90,36,cream,true);DrawMap(new(w*.32f,h*.51f),220,true);
            float x=w*.60f;Text("Your crew",x,150,24,cream,true);
            for(int i=0;i<r.Crew.Count;i++)
            {
                var m=r.Crew[i];float y=211+i*103;Text(m.Name,x,y,22,cream,true);
                Text($"{m.Role} · rank {m.Level}",x,y+24,13,gold);
                Text(m.Effect,x,y+47,13,muted);
            }
            Text($"{r.Crew.Count} / 4 berths",x,665,13,muted);
            Text(sailing?"W/S sail & brake  ·  A/D helm  ·  Shift full sail  ·  C cruise":"WASD / click move  ·  Space jump & glide  ·  Shift dodge  ·  Q/R camera",70,h-72,14,cream);
            Text("TAB to return",70,h-38,13,muted);
        }
        if(r.Mode==RunMode.Choosing)DrawChoices();
        if(r.Mode==RunMode.Dead)DrawDeath();
        if(Game.Paused){DrawRect(new(0,0,w,h),new Color(new Color("111f23"),.93f));Center("Paused",h/2-20,42,cream,true);Center("Escape to continue",h/2+30,15,muted);}
    }
    void DrawTitle()
    {
        float w=dimensions.X,h=dimensions.Y;
        Text("A Little Further",66,h*.68f,62,cream,true);
        Text("Set sail",70,h*.68f+61,19,cream);
        DrawLine(new(70,h*.68f+72),new(133,h*.68f+72),cream,1);
        Text("Enter",70,h*.68f+104,12,new Color(cream,.65f));
    }
    void DrawMap(Vector2 center,float radius,bool big)
    {
        var r=Game.Run;DrawCircle(center,radius+3,new Color(gold,.55f));DrawCircle(center,radius,ink);
        bool ashore=r.Mode!=RunMode.Sailing && r.Current!=null;
        var focus=ashore?r.Current!.Center:r.Position;
        float scale=ashore?radius/(r.Current!.Radius*1.3f):.064f;
        Vector2 Point(V2 p)=>center+new Vector2(p.X-focus.X,-(p.Y-focus.Y))*scale;
        for(int i=0;i<4;i++){float a=i*Mathf.Pi/2;DrawLine(center+Vector2.FromAngle(a)*radius*.85f,center+Vector2.FromAngle(a)*radius,new Color(gold,.4f),1);}
        Text("N",center.X-4,center.Y-radius+17,10,gold);
        foreach(Cell c in r.World.Visible(r.Position,big?2:3))
        {
            var island=r.World.IslandAt(c);if(!r.Visited.Contains(c) && !r.World.InSight(island,r.Position))continue;
            Vector2 p=Point(island.Center);if(p.DistanceTo(center)>radius-13)continue;
            float rr=MathF.Max(3,island.Radius*scale*.48f);
            if(ashore && c==r.Current!.Cell)
            {
                var outline=new Vector2[64];
                for(int j=0;j<64;j++)
                {
                    float a=j*Mathf.Tau/64,phase=island.Seed%19;
                    float shape=1+.07f*MathF.Sin(a*3+phase)+.035f*MathF.Sin(a*7+phase*.31f);
                    float extent=(shape*island.Radius-1)/MathF.Sqrt(MathF.Pow(MathF.Cos(a)/1.1f,2)+MathF.Pow(MathF.Sin(a)/.96f,2));
                    outline[j]=Point(island.Center+new V2(MathF.Cos(a),MathF.Sin(a))*extent);
                }
                DrawColoredPolygon(outline,new("45675b"));DrawPolyline(outline.Append(outline[0]).ToArray(),new("acb28d"),1.5f,true);
                foreach(var route in IslandLayout.Routes(island))DrawPolyline(route.Select(q=>Point(island.Center+q)).ToArray(),new Color(gold,.45f),1.5f,true);
                var bell=Point(island.Shrine);DrawCircle(bell,5,r.Claimed.Contains(c)?muted:gold);Text("Bell",bell.X+9,bell.Y+4,12,cream);
                for(int j=8;j<IslandLayout.TreasureCount;j++)if(r.Treasure.Contains((c,j)))DrawCircle(Point(IslandLayout.Treasure(island,j)),3,muted);
                Text(island.Name,center.X-radius,center.Y+radius+34,16,cream,true);
            }
            else
            {
                DrawCircle(p,rr,r.Visited.Contains(c)?new("749673"):new("476864"));
                if(r.Claimed.Contains(c))Text("✓",p.X-5,p.Y+4,12,cream);
                if(big)Text(island.Name,p.X-30,p.Y+rr+16,10,cream);
            }
            Vector2 port=Point(island.Landing);DrawCircle(port,ashore?5:3,gold);if(ashore)Text("Landing",port.X+10,port.Y+4,12,cream);
        }
        Vector2 player=Point(r.Position),heading=new(MathF.Sin(r.Heading),-MathF.Cos(r.Heading)),side=new(-heading.Y,heading.X);
        DrawColoredPolygon([player+heading*8,player-heading*5+side*4,player-heading*5-side*4],cream);
    }
    void DrawCombat()
    {
        var run=Game.Run;if(run.Mode!=RunMode.Exploring)return;
        foreach(var e in run.Enemies)
        {
            Vector3 p=Art.At(e.Position,run.World.Height(e.Position)+2.2f);if(Game.Camera.IsPositionBehind(p))continue;Vector2 screen=Game.Camera.UnprojectPosition(p);
            if(e.Hp<e.MaxHp){DrawRect(new(screen.X-17,screen.Y-8,34,4),ink);DrawRect(new(screen.X-17,screen.Y-8,34*MathF.Max(0,e.Hp/e.MaxHp),4),Art.Coral);}
            if(e.Windup>0){Vector2 ground=Game.Camera.UnprojectPosition(p-Vector3.Up*2);DrawArc(ground,e.Kind==1?41:25,0,Mathf.Tau,40,new Color(Art.Coral,.9f),3,true);Text("!",screen.X-4,screen.Y-16,23,gold);}
            if(e.Marked)DrawCircle(screen+new Vector2(0,-18),3,new("92e4e1"));
        }
    }
    void DrawChoices()
    {
        float w=dimensions.X,h=dimensions.Y;var r=Game.Run;DrawRect(new(0,0,w,h),new Color(new Color("111f23"),.97f));
        Center("Choose a hand",h*.22f,42,cream,true);Center("Recruit, or improve a current crew member.",h*.22f+43,15,muted);
        for(int i=0;i<r.Offers.Length;i++)
        {
            Role role=r.Offers[i];var mate=new Mate(role);float x=w/2-462+i*314;Panel(new(x,h*.36f,294,248),new("243035"));
            DrawCircle(new(x+42,h*.36f+44),14,Game.RoleColor(role));Text((i+1).ToString(),x+37,h*.36f+49,14,ink);
            Text(mate.Name,x+26,h*.36f+101,31,cream,true);Text(role.ToString().ToUpperInvariant(),x+26,h*.36f+130,11,gold);
            string[] lines=mate.Effect.Split(" · ");for(int j=0;j<lines.Length;j++)Text(lines[j],x+26,h*.36f+166+j*23,13,muted);
            Text(r.Crew.Any(m=>m.Role==role)?"DEVELOP  →":"RECRUIT  →",x+26,h*.36f+228,12,gold);
        }
        Center("1 / 2 / 3  or click a card",h*.36f+292,13,cream);
        if(r.Crew.Count==4)Center($"New roles replace {r.Crew[r.SelectedReplacement].Name}. Press R to choose a berth.",h*.36f+327,14,gold);
        else Center($"{r.Crew.Count} of 4 berths filled",h*.36f+327,13,muted);
    }
    void DrawDeath()
    {
        float w=dimensions.X,h=dimensions.Y;var r=Game.Run;DrawRect(new(0,0,w,h),new Color(ink,.94f));Center("Voyage ended",h*.30f,46,cream,true);
        Center("Everything begins again.",h*.30f+49,16,muted);
        Center($"{r.IslandsVisited} islands     {r.Shrines} {(r.Shrines==1?"bell":"bells")}     {r.Gold} doubloons     {r.Kills} foes",h*.30f+114,20,gold);
        Panel(new(w/2-168,h*.30f+165,336,57),gold,5);Center("ENTER  ·  A NEW VOYAGE",h*.30f+201,16,ink);
        Center("A fresh island. A new crew.",h*.30f+258,13,muted);
    }
    public void Click(Vector2 p)
    {
        if(Game.Title){Game.Start();return;}
        if(Game.Run.Mode==RunMode.Dead){Game.Restart();return;}
        if(Game.Run.Mode!=RunMode.Choosing)return;
        for(int i=0;i<3;i++)if(new Rect2(dimensions.X/2-462+i*314,dimensions.Y*.36f,294,248).HasPoint(p)){Game.Select(i);break;}
    }
}
