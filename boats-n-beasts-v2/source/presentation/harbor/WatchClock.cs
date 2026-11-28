using BoatsNBeasts.Core;
using System.Diagnostics;

namespace BoatsNBeasts;

internal sealed class WatchClock(WatchHours initial)
{
    long last=Stopwatch.GetTimestamp(),lastAction=Stopwatch.GetTimestamp();
    WatchHours record=initial;
    double harbor=initial.Harbor, underway=initial.Underway, unsaved;
    public WatchHours Hours=>record with{Harbor=harbor,Underway=underway};
    public bool Due => unsaved>=45;
    public void Filed()=>unsaved=0;
    public void Touch()=>lastAction=Stopwatch.GetTimestamp();
    public void Tick(bool sailing,bool running)
    {
        long now=Stopwatch.GetTimestamp();double seconds=Stopwatch.GetElapsedTime(last,now).TotalSeconds;last=now;
        if(!running || seconds>3 || Stopwatch.GetElapsedTime(lastAction,now).TotalMinutes>=2)return;
        if(sailing)underway+=seconds;
        else harbor+=seconds;
        unsaved+=seconds;
    }
    public void Depart(){record=record.CastOff();Touch();}
    public void Land(bool won)=>record=record.MakePort(won);
    public void Finish(){if(record.FirstClear==null)record=record with{FirstClear=harbor+underway};}
    internal static string Elapsed(double duration)
    {
        int minutes=(int)(duration/60);
        return minutes>=60?$"{minutes/60}h {minutes%60:00}m":$"{minutes}m";
    }
}

internal partial class LastLightHarbor
{
    internal WatchClock? Clockbook;
    void HoursAtSea()
    {
        if(Clockbook==null)return;
        var r=Clockbook.Hours;
        string total=$"{WatchClock.Elapsed(r.Underway)} on expeditions and voyages, {WatchClock.Elapsed(r.Harbor)} in harbor. "+
            $"{r.Departures} departures, {r.Returns} successful returns, {r.Losses} retreats or losses.";
        if(r.FirstClear is {} win)total+=" The final homecoming was signed after "+WatchClock.Elapsed(win)+".";
        Open("THE CAPTAIN’S LOG","Hours on watch",total+" The clock follows active play and reading. It stops at anchor, in the background, and after two minutes without input.");
        Choice("Close the log",Close,true);
    }
}
