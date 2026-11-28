using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal partial class PostMap : Control
{
    internal PostalCircuit Watch=null!;
    internal Action<int>? Select;
    internal int Selected=-1;
    static readonly Color Ink=new("284754"), Shoal=new("afba96"), Paper=new("e9d3a2"), Red=new("a14e38"), Jade=new("327568");
    static readonly Font Face=new SystemFont{FontNames=["Baskerville","Georgia","serif"]};
    Vector2 Mark(int i)
    {
        var v=Watch.Chart[i];
        return new Vector2(42,104)+new Vector2((Size.X-84)*v.X,(Size.Y-184)*v.Y);
    }
    void Caption(Vector2 pos,string value,int size,Color tint) => DrawString(Face,pos,value,fontSize:size,modulate:tint);
    public override void _Draw()
    {
        DrawRect(new(Vector2.Zero,Size),Paper);DrawRect(new(new Vector2(9,9),Size-Vector2.One*18),Ink,false,1.4f);
        Caption(new(25,45),"Packet lanes",30,Ink);
        Caption(new(26,71),"Circles mark the addresses on this watch.",17,Ink);
        foreach(var lane in Watch.Lanes)
        {
            bool open=lane.From==Watch.Port || lane.To==Watch.Port;
            var a=Mark(lane.From);var b=Mark(lane.To);
            DrawDashedLine(a,b,open?Red:new Color(Ink,.41f),open?2.8f:1.6f,lane.Duty==SeaDuty.Landing?3:9);
        }
        for(int i=0;i<Watch.Chart.Length;i++)
        {
            var at=Mark(i);
            if(i is >=1 and <=4)
            {
                var outline=new Vector2[13];
                for(int j=0;j<outline.Length;j++)
                {
                    float angle=j*Mathf.Tau/outline.Length;
                    float r=20+6*Mathf.Sin(angle*(i+2)+i);
                    outline[j]=at+new Vector2(Mathf.Cos(angle)*1.2f,Mathf.Sin(angle)*.63f)*r;
                }
                DrawColoredPolygon(outline,Shoal);
            }
            if(Watch.Goal(i)>0)DrawCircle(at,18,Red,false,2,true);
            if(Selected==i)DrawArc(at,22,0,Mathf.Tau,32,Jade,2.4f,true);
            DrawCircle(at,i==Watch.Port?8:5,Watch.Visited(i)?Jade:Ink);
            if(i==Watch.Port)
                DrawColoredPolygon([at+new Vector2(0,-3),at+new Vector2(0,-24),at+new Vector2(15,-17),at+new Vector2(2,-13)],Red);
            string label=Watch.Name(i);float w=Face.GetStringSize(label,fontSize:18).X;
            var p=new Vector2(Math.Clamp(at.X-w/2,14,Math.Max(14,Size.X-w-14)),at.Y+33);
            DrawRect(new(p-new Vector2(3,18),new(w+6,23)),new Color(Paper,.92f));
            Caption(p,label,18,Ink);
        }
        Caption(new(25,Size.Y-24),"Red lanes depart from your berth. Dotted lanes follow a towpath.",15,Ink);
    }
    public override void _GuiInput(InputEvent input)
    {
        if(input is not InputEventMouseButton{Pressed:true,ButtonIndex:MouseButton.Left} click)return;
        int close=Enumerable.Range(0,Watch.Chart.Length).MinBy(i=>Mark(i).DistanceSquaredTo(click.Position));
        if(Mark(close).DistanceTo(click.Position)<=49){Select?.Invoke(close);AcceptEvent();}
    }
}
