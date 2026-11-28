using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public bool CallShipmate(Shipmate mate)
    {
        if(Mode!=VoyageMode.Sailing || Health<=0)return false;
        switch(mate)
        {
            case Shipmate.Vara when Health<MaxHealth:
                Patch(45);return true;
            case Shipmate.Lio:
                var caught=Enemies.Where(e=>e.Health>0 && Vector2.Distance(e.Position,Position)<720)
                    .OrderBy(e=>Vector2.DistanceSquared(e.Position,Position)).Take(3).ToArray();
                foreach(var enemy in caught)Grapple(enemy);
                return caught.Length>0;
            case Shipmate.Nell:
                Shots.RemoveAll(s=>s.Hostile);Invulnerable=Math.Max(Invulnerable,4);
                Events.Add(new("guard",Position,1));return true;
            default:return false;
        }
    }
}
public sealed partial class LandingYard
{
    public bool CallShipmate(Shipmate mate)
    {
        if(Phase==YardPhase.Lost || Boarded)return false;
        switch(mate)
        {
            case Shipmate.Vara when Health<MaximumHealth:
                Health=Math.Min(MaximumHealth,Health+4);Say("Vara opens the thermos and passes round the broth.");return true;
            case Shipmate.Lio:
                var caught=Foes.Where(e=>e.Health>0 && Vector2.Distance(e.Position,Player)<6)
                    .OrderBy(e=>Vector2.DistanceSquared(e.Position,Player)).Take(3).ToArray();
                foreach(var foe in caught)
                {
                    foe.Stagger=2.6f;foe.Rush=0;foe.Hit=.3f;
                    Attacks.RemoveAll(attack=>attack.Source==foe);
                }
                if(caught.Length>0)Say("Lio catches their feet in his spare line.");
                return caught.Length>0;
            case Shipmate.Nell:
                Attacks.Clear();safe=Math.Max(safe,4);Say("Nell sounds the quiet bell. The way is clear for four beats.");return true;
            default:return false;
        }
    }
}
