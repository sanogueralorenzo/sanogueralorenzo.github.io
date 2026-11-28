namespace BoatsNBeasts.Core;

public sealed record WatchHours(double Harbor=0,double Underway=0,int Departures=0,int Returns=0,int Losses=0,
    bool Away=false,double? FirstClear=null)
{
    public WatchHours CastOff()=>this with{ Away=true,Departures=Departures+1 };
    public WatchHours MakePort(bool won)=>!Away?this:this with{
        Away=false,Returns=Returns+(won?1:0),Losses=Losses+(won?0:1) };
}
