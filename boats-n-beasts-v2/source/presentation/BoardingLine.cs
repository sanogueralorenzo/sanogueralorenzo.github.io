using Godot;

namespace BoatsNBeasts;

static class BoardingLine
{
    static readonly Color Shade=new("60493d"),Rope=new("d79c5d"),Twine=new("ffe6a2"),Metal=new("abc7bd");

    public static void Draw(Control canvas,Vector2 a,Vector2 b,float slack,bool taut)
    {
        var delta=b-a;
        float length=delta.Length();
        if(length<8)return;
        var along=delta/length;
        var across=new Vector2(-along.Y,along.X);
        float bow=Math.Clamp(length*.085f,2,27)*Math.Clamp(slack,0,1);
        Vector2 Cord(float t)=>a+delta*t+Vector2.Down*(4*t*(1-t)*bow);
        var curve=new Vector2[15];
        for(int i=0;i<curve.Length;i++)curve[i]=Cord(i/(curve.Length-1f));
        canvas.DrawPolyline(curve,Shade,7.0f,true);
        canvas.DrawPolyline(curve,taut?new("e7ba6d"):Rope,4.6f,true);
        int turns=Math.Clamp((int)(length/10),2,80);
        for(int i=0;i<turns;i++)
        {
            var mid=Cord((i+.6f)/turns);
            canvas.DrawLine(mid-along*2.5f-across*1.6f,mid+along*2.1f+across*.9f,Twine,1.5f,true);
        }
        var eye=b-along*9;
        canvas.DrawArc(eye,4.8f,0,Mathf.Tau,12,Shade,4,true);
        canvas.DrawArc(eye,4.8f,0,Mathf.Tau,12,Twine,2,true);
        foreach(int side in new[]{-1,1})
        {
            Vector2[] iron=[eye+along*3,b+along*5+across*(side*1.7f),b+along*3+across*(side*8.1f),b-along*1.8f+across*(side*8.8f)];
            canvas.DrawPolyline(iron,Shade,4.9f,true);
            canvas.DrawPolyline(iron,Metal,2.6f,true);
        }
    }
}
