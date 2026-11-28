using System.Numerics;

namespace BoatsNBeasts.Core;

public enum ProofMethod { Join, Balance, Impression, Sound }
public sealed partial class PrizeBoarding
{
    public ProofMethod Method { get; }
    public int Examination { get; private set; }
    public bool Examining => Work == DeckWork.Search && Examination > 0 && !Fixed;
    public bool Carrying => Examining && Method == ProofMethod.Balance && Examination == 2;
    public string ExhibitCall => Method switch
    {
        ProofMethod.Join => "The original has a matching half. Take it to the joiner, then close the jaws over the paired marks.",
        ProofMethod.Balance => "The declaration names a weight. Tare the empty pan, carry the sample across, then weigh the signed foil.",
        ProofMethod.Sound => "The exhibit has a voice. Try the low rest, compare the high tongue, then draw the sound on the witness board.",
        _ => "The mark sits below the surface. Warm the wax, take an impression, then take it to the reader’s light."
    };
    public Vector2[] BenchPoints => [new(-3.1f, .58f), new(.14f, 2.14f), new(3.03f, .65f)];
    public string[] BenchNames => Method switch
    {
        ProofMethod.Join => ["Joiner’s rack", "Mating jaws", "Witness lamp"],
        ProofMethod.Balance => ["Empty pan", "Sample pan", "Signed foil"],
        ProofMethod.Sound => ["Low rest", "High tongue", "Sound board"],
        _ => ["Wax lamp", "Impression press", "Reader’s light"]
    };
    public Vector2 Bench => BenchPoints[Examination - 1];
    static ProofMethod ReadMaterial(string name)
    {
        bool Has(params string[] clues) => clues.Any(clue => name.Contains(clue, StringComparison.OrdinalIgnoreCase));
        if (Has("paired", "graft", "board", "hinge", "shackle", "suit", "button", "key", "window", "leaf", "skin", "cap", "plank")) return ProofMethod.Join;
        if (Has("stone", "bowl", "plate", "pear", "pan", "kitchen", "fuel", "weight", "shelter", "ballast", "pillow")) return ProofMethod.Balance;
        if (Has("ribbon", "lamp", "footlight", "whistle", "tune", "wick", "note", "drum", "bell", "time", "sheet")) return ProofMethod.Sound;
        return ProofMethod.Impression;
    }
    void BeginExamination()
    {
        Examination = 1; Call = ExhibitCall; Version++;
    }
    void Examine()
    {
        var benches = BenchPoints;
        int station = Enumerable.Range(0, benches.Length).MinBy(i => Vector2.DistanceSquared(Player, benches[i]));
        if (Vector2.Distance(Player, benches[station]) > 1.03f) return;
        if (station != Examination - 1)
        {
            Call = "The reference is still at the " + BenchNames[Examination - 1].ToLowerInvariant() + ".";
            return;
        }
        if (Examination < 3)
        {
            Examination++;
            Call = Examination == 2 ? $"Now bring {Watch.Exhibit.Item} to the {BenchNames[1].ToLowerInvariant()}." : $"The original carries {Watch.Exhibit.Mark}. Compare the record at the {BenchNames[2].ToLowerInvariant()}.";
        }
        else
        {
            Fixed = true; Silver += 4; Watch.RecordFinding(); Call = Watch.Exhibit.Finding;
        }
        Version++;
    }
    public bool CallShipmate(Shipmate mate)
    {
        if (Won || Lost) return false;
        switch (mate)
        {
            case Shipmate.Vara when Health < MaxHealth:
                Health = Math.Min(MaxHealth, Health + 4); Call = "Vara passes four measures from her brass thermos."; break;
            case Shipmate.Lio:
                var nearby = Guards.Where(g => g.Health > 0 && Vector2.DistanceSquared(g.Position, Player) < 3.8f * 3.8f).ToArray();
                if (nearby.Length == 0) return false;
                foreach (var foe in nearby) { foe.Stun = 2.5f; foe.Tell = foe.Dash = 0; }
                HookEnd = nearby[0].Position; Rope = .65f; Call = "Lio draws the guards’ lines together."; break;
            case Shipmate.Nell:
                hurt = Math.Max(hurt, 4); Call = "Nell rings four quiet beats to cross the deck."; break;
            default: return false;
        }
        Version++; return true;
    }
}
