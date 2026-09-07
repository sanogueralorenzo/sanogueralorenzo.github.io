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
    void Text(string text,float x,float y,int size,Color color,bool display=false)=>DrawString(display?serif:font,new(x,y),text,HorizontalAlignment.Left,-1,size,color);
    void Center(string text,float y,int size,Color color,bool display=false){float width=(display?serif:font).GetStringSize(text,HorizontalAlignment.Left,-1,size).X;Text(text,(dimensions.X-width)*.5f,y,size,color,display);}
    void Panel(Rect2 rect,Color color,float radius=12)
    {
        var box=new StyleBoxFlat{BgColor=color,CornerRadiusTopLeft=(int)radius,CornerRadiusTopRight=(int)radius,CornerRadiusBottomLeft=(int)radius,CornerRadiusBottomRight=(int)radius,BorderColor=new Color(gold,.16f),BorderWidthBottom=1,BorderWidthTop=1,BorderWidthLeft=1,BorderWidthRight=1};DrawStyleBox(box,rect);
    }
    public override void _Ready(){MouseFilter=MouseFilterEnum.Ignore;SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);}
    public override void _Draw()
    {
        if(Game.Run==null)return;var r=Game.Run;float w=dimensions.X,h=dimensions.Y;
        if(Game.Title){DrawTitle();return;}
        Panel(new(24,24,258,91),new Color(ink,.92f));Text("CAPTAIN’S LOG",43,49,12,gold);Text(r.Nearest.Name,43,78,22,cream,true);Text(r.Mode==RunMode.Sailing?"UNDER SAIL":"ASHORE",43,100,11,muted);
        Panel(new(w/2-158,24,316,47),new Color(ink,.91f));Center($"{r.Gold}  DOUBLOONS      {r.Shrines}  BELLS      {r.Kills}  FOES",54,12,cream);
        Panel(new(24,h-126,280,98),new Color(ink,.94f));Text("CAPTAIN",43,h-98,11,gold);Text($"{MathF.Ceiling(r.Health)} / 100",206,h-98,12,cream);
        DrawRect(new(43,h-83,240,10),new("34535a"));DrawRect(new(43,h-83,240*r.Health/100,10),new("d57c63"));
        DrawRect(new(43,h-61,240,4),new("34535a"));DrawRect(new(43,h-61,240*r.Stamina,4),new("9dc5a6"));
        Text(r.DodgeCooldown>0?"DODGE RECHARGING":"SHIFT  ·  DODGE READY",43,h-40,10,muted);
        for(int i=0;i<4;i++)
        {
            float x=322+i*146;Panel(new(x,h-102,135,74),new Color(ink,.92f));
            if(i<r.Crew.Count){Mate m=r.Crew[i];DrawCircle(new(x+19,h-80),5,Game.RoleColor(m.Role));Text(m.Name.ToUpperInvariant(),x+32,h-75,11,cream);Text(m.Role.ToString(),x+14,h-54,12,Game.RoleColor(m.Role));Text("RANK "+m.Level,x+14,h-37,10,muted);}
            else{Text("+",x+60,h-68,23,muted);Text("OPEN BERTH",x+29,h-42,10,muted);}
        }
        string controls=r.Mode==RunMode.Sailing?"W S  sail / brake     A D  helm     SHIFT  full sail     C  cruise     TAB  chart":"W A S D / click  move     SPACE  jump / hold to glide     SHIFT  dodge     Q R  camera";
        Text(controls,26,h-12,11,new Color(cream,.9f));
        if(r.Prompt.Length>0){float tw=font.GetStringSize(r.Prompt,HorizontalAlignment.Left,-1,16).X;Panel(new(w/2-tw/2-24,h-174,tw+48,45),new Color(ink,.96f));Center(r.Prompt,h-145,16,gold);}
        if(r.NoticeTime>0){Panel(new(w/2-300,87,600,45),new Color(ink,.87f));Center(r.Notice,115,14,cream);}
        DrawMap(new(w-113,115),76,false);
        Panel(new(w-195,199,168,54),new Color(ink,.9f));
        Text($"TIDE {MathF.Floor(r.Threat):0}  ·  {(int)r.Time/60:00}:{(int)r.Time%60:00}",w-190,222,12,gold);
        Text("TAB  ·  CHART",w-160,242,10,muted);
        DrawCombat();
        if(Game.IsValidation)Text("AUTOMATED NATIVE PLAYTHROUGH",w-280,h-15,10,muted);
        if(Game.Chart){Panel(new(w/2-280,h/2-275,560,550),new Color(ink,.98f));Center("Waters still unwritten",h/2-218,28,cream,true);DrawMap(new(w/2,h/2+10),195,true);Center("Amber: landing · ivory: shrine · blue: your ship",h/2+244,12,muted);}
        if(r.Mode==RunMode.Choosing)DrawChoices();
        if(r.Mode==RunMode.Dead)DrawDeath();
        if(Game.Paused){DrawRect(new(0,0,w,h),new Color(ink,.82f));Center("At anchor",h/2-25,48,cream,true);Center("ESC  ·  Continue the voyage",h/2+27,16,gold);Center("No run saves. Closing the game ends this voyage.",h/2+75,13,muted);}
    }
    void DrawTitle()
    {
        float w=dimensions.X,h=dimensions.Y;DrawRect(new(0,0,w*.49f,h),new Color(ink,.89f));
        Text("AN UNCHARTED PIRATE VOYAGE",64,h*.25f,12,gold);
        Text("A Little",61,h*.25f+83,67,cream,true);Text("Further",61,h*.25f+158,67,cream,true);
        DrawLine(new(64,h*.25f+188),new(143,h*.25f+188),gold,2);
        Text("One boat. Four berths. An endless horizon.",64,h*.25f+229,17,cream);
        Text("Sail to strange shores. Climb a little higher.",64,h*.25f+261,14,muted);
        Text("Build a crew worth getting lost with.",64,h*.25f+286,14,muted);
        Panel(new(64,h*.25f+324,274,55),gold,4);Text("SET SAIL     →",109,h*.25f+360,17,ink);
        Text("ENTER  /  CLICK TO BEGIN",64,h*.25f+408,10,muted);
        Text("A fresh voyage after every fall. Nothing to retrieve.",64,h-50,12,muted);
        Text("MARIGOLD WATERS  /  FAIR WIND",w-337,h-35,11,cream);
    }
    void DrawMap(Vector2 center,float radius,bool big)
    {
        var r=Game.Run;DrawCircle(center,radius+3,new Color(gold,.55f));DrawCircle(center,radius,ink);
        float scale=big?.77f:.23f;
        for(int i=0;i<4;i++){float a=i*Mathf.Pi/2;DrawLine(center+Vector2.FromAngle(a)*radius*.85f,center+Vector2.FromAngle(a)*radius,new Color(gold,.4f),1);}
        Text("N",center.X-4,center.Y-radius+17,10,gold);
        foreach(Cell c in r.World.Visible(r.Position,big?2:3))
        {
            var island=r.World.IslandAt(c);Vector2 p=center+new Vector2(island.Center.X-r.Position.X,-(island.Center.Y-r.Position.Y))*scale;
            if(p.DistanceTo(center)>radius-13)continue;
            float rr=MathF.Max(3,island.Radius*scale*.48f);DrawCircle(p,rr,r.Visited.Contains(c)?new("749673"):new("476864"));
            Vector2 port=center+new Vector2(island.Landing.X-r.Position.X,-(island.Landing.Y-r.Position.Y))*scale;DrawCircle(port,3,gold);
            if(r.Claimed.Contains(c))Text("✓",p.X-5,p.Y+4,12,cream);
            if(big)Text(island.Name,p.X-30,p.Y+rr+16,10,cream);
        }
        Vector2 heading=new(MathF.Sin(r.Heading),-MathF.Cos(r.Heading));Vector2 side=new(-heading.Y,heading.X);
        DrawColoredPolygon([center+heading*8,center-heading*5+side*4,center-heading*5-side*4],cream);
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
        float w=dimensions.X,h=dimensions.Y;var r=Game.Run;DrawRect(new(0,0,w,h),new Color(ink,.90f));
        Center("A bell rung. A bond made.",h*.22f,42,cream,true);Center("Recruit a new hand, or deepen an existing bond.",h*.22f+43,15,muted);
        for(int i=0;i<r.Offers.Length;i++)
        {
            Role role=r.Offers[i];var mate=new Mate(role);float x=w/2-462+i*314;Panel(new(x,h*.36f,294,248),new("244b53"));
            DrawCircle(new(x+42,h*.36f+44),14,Game.RoleColor(role));Text((i+1).ToString(),x+37,h*.36f+49,14,ink);
            Text(mate.Name,x+26,h*.36f+101,31,cream,true);Text(role.ToString().ToUpperInvariant(),x+26,h*.36f+130,11,gold);
            string[] lines=mate.Effect.Split(" · ");for(int j=0;j<lines.Length;j++)Text(lines[j],x+26,h*.36f+166+j*23,13,muted);
            Text(r.Crew.Any(m=>m.Role==role)?"DEVELOP  →":"RECRUIT  →",x+26,h*.36f+228,12,gold);
        }
        Center("1 / 2 / 3  or click a card",h*.36f+292,13,cream);
        if(r.Crew.Count==4)Center($"New roles replace {r.Crew[r.SelectedReplacement].Name}. Press R to choose a berth.",h*.36f+327,14,gold);
        else Center($"{r.Crew.Count} of 4 berths filled · Storm marks empower Flint’s gunfire",h*.36f+327,13,muted);
    }
    void DrawDeath()
    {
        float w=dimensions.X,h=dimensions.Y;var r=Game.Run;DrawRect(new(0,0,w,h),new Color(ink,.94f));Center("The sea keeps its stories.",h*.30f,46,cream,true);
        Center("Your voyage has ended. The next horizon is a fresh beginning.",h*.30f+49,16,muted);
        Center($"{r.IslandsVisited} islands     {r.Shrines} {(r.Shrines==1?"bell":"bells")}     {r.Gold} doubloons     {r.Kills} foes",h*.30f+114,20,gold);
        Panel(new(w/2-168,h*.30f+165,336,57),gold,5);Center("ENTER  ·  A NEW VOYAGE",h*.30f+201,16,ink);
        Center("No checkpoints. No recovery. Just a little further.",h*.30f+258,13,muted);
    }
    public void Click(Vector2 p)
    {
        if(Game.Title){Game.Start();return;}
        if(Game.Run.Mode==RunMode.Dead){Game.Restart();return;}
        if(Game.Run.Mode!=RunMode.Choosing)return;
        for(int i=0;i<3;i++)if(new Rect2(dimensions.X/2-462+i*314,dimensions.Y*.36f,294,248).HasPoint(p)){Game.Select(i);break;}
    }
}
