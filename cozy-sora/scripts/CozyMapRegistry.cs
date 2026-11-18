using Godot;

namespace CozySora;

[GlobalClass]
public partial class CozyMapRegistry : Resource
{
    [Export] public Godot.Collections.Array<CozyMapDefinition> Maps { get; set; } = new();

    public CozyMapDefinition? FindMap(StringName id) => Maps.FirstOrDefault(destination => destination.Id == id);

    public string ValidationError()
    {
        var ids = new HashSet<StringName>();
        foreach (var destination in Maps)
        {
            if (destination is null || destination.Id.IsEmpty) return "A destination needs a stable ID.";
            if (!ids.Add(destination.Id)) return "Destination IDs must be unique.";
            if (destination.Title.Length == 0 || destination.Preview is null) return "A destination needs a title and preview.";
            if (!ResourceLoader.Exists(destination.Scene)) return "A destination scene is unavailable.";
        }
        return Maps.Count == 0 ? "No destinations are registered." : "";
    }
}
