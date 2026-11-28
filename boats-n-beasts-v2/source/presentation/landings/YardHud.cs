using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class YardHud : Control
{
    public KilnExpedition Trip=null!;
    Font font=null!;
    static readonly Color Deep=new("122e39ee"),Parchment=new("fff1d2"),Gold=new("f0c581"),Mint=new("92dfbf");
    public override void _Ready(){MouseFilter=MouseFilterEnum.Ignore;font=ThemeDB.FallbackFont;}
    public override void _Draw()
    {
        var y=Trip.Yard;var w=Size.X;var h=Size.Y;
        Box(new(22,20,530,107));
        Text(40,47,$"{(y.Order.Island.Length>0?y.Order.Island:y.Order.Region).ToUpperInvariant()}    ·    {y.District+1} / {y.LegCount}",17,Gold);
        Text(40,78,y.DistrictName,25,Parchment);Text(40,109,y.Objective,19,Mint);
        if(y.Foes.FirstOrDefault(f=>f.Kind==YardBeast.Guardian) is {} boss)
        {
            Box(new(w-370,20,348,71));Text(w-352,49,y.Order.Boss.ToUpperInvariant(),20,Gold);
            DrawRect(new(w-351,62,306,10),new("603f46"));
            DrawRect(new(w-351,62,306f*boss.Health/boss.Maximum,10),new("f18864"));
        }
        if(y.CanTrade)
        {
            Box(new(22,138,414,145));Text(39,165,$"TRADE TARP   ·   {y.Chits} chits",17,Gold);
            Text(39,192,"1   Hot ration  +5 vitality   ·   1 chit",18,Parchment);
            Text(39,217,$"2   Temper blade  {y.Edge}/3   ·   2 chits",18,Parchment);
            Text(39,242,$"3   Shorten hook reel  {y.Quickline}/3   ·   2 chits",18,Parchment);
            Text(39,267,y.District+2<y.LegCount?"4   Charter bypass  ·  4 chits":"Last ferry takes the marked gate",17,Mint);
        }
        var labels=Trip.Locations().ToArray();
        for(int i=0;i<labels.Length;i++)Beacon(labels[i].Position,labels[i].Name,i,labels.Length);
        foreach(var b in y.Foes.Where(f=>f.Kind!=YardBeast.Guardian))
        {
            var at=Trip.Stage.Lens.UnprojectPosition(Trip.Point(b.Position,1.18f));
            DrawRect(new(at.X-20,at.Y,40,5),Deep);DrawRect(new(at.X-20,at.Y,40f*b.Health/b.Maximum,5),Gold);
        }
        Box(new(22,h-58,466,40));
        Text(39,h-32,$"Vitality   {y.Health}/{y.MaximumHealth}       {y.Silver} silver       {y.Chits} chits",18,Mint);
        Box(new(w-630,h-58,608,40));
        Text(w-614,h-32,$"WASD  Move     J  Cut     K  {(y.HookWait>0?$"Hook {y.HookWait:0.0}s":"Hook")}     Space  Dodge     E  Work",18,Parchment);
        if(y.LineClock>0&&y.Phase!=YardPhase.Lost)
        {
            const float max=940;
            float width=Math.Min(max,font.GetStringSize(y.Line,fontSize:19).X+32);
            var measured=font.GetMultilineStringSize(y.Line,HorizontalAlignment.Center,width-28,19);
            float height=measured.Y+13;
            Box(new((w-width)/2,h-78-height,width,height));
            DrawMultilineString(font,new((w-width)/2+14,h-77-height+20),y.Line,HorizontalAlignment.Center,width-28,19,-1,Parchment);
        }
        if(y.Phase==YardPhase.Lost)
        {
            DrawRect(new(0,0,w,h),new Color("0e2433bd"));
            DrawString(font,new(0,h*.45f),"The crew rows for home",HorizontalAlignment.Center,w,38,Parchment);
            DrawString(font,new(0,h*.45f+53),$"E   Return with {y.Silver} silver",HorizontalAlignment.Center,w,22,Gold);
        }
    }
    void Beacon(System.Numerics.Vector2 p,string name,int index,int count)
    {
        var at=Trip.Stage.Lens.UnprojectPosition(Trip.Point(p,.93f));
        float width=font.GetStringSize(name,fontSize:16).X+24;
        var pos=at.Clamp(new Vector2(width/2+20,157),new Vector2(Size.X-width/2-20,Size.Y-169));
        bool outside=at.DistanceSquaredTo(pos)>2;
        if(outside&&pos.Y==157&&count>1)pos.X=Mathf.Clamp(pos.X,Size.X*(index+.40f)/(count+.25f)-width*.3f,Size.X*(index+.60f)/(count+.25f)+width*.3f);
        Box(new(pos.X-width/2,pos.Y-14,width,28));Text(pos.X-width/2+12,pos.Y+6,name,16,Gold);
        if(outside)
        {
            var dir=(at-pos).Normalized();var side=new Vector2(-dir.Y,dir.X)*4;
            var origin=pos+dir*(Math.Abs(dir.X)*width*.5f+14);
            DrawColoredPolygon([origin+dir*9,origin-side,origin+side],Gold);
        }
    }
    void Box(Rect2 r){DrawRect(r,Deep);DrawLine(r.Position,r.Position+new Vector2(r.Size.X,0),Gold,1.5f);}
    void Text(float x,float y,string s,int size,Color tone)=>DrawString(font,new(x,y),s,HorizontalAlignment.Left,-1,size,tone);
}
