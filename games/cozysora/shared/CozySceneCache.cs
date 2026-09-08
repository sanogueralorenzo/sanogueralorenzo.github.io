using Godot;
using System.Security.Cryptography;
using System.Text;
using FileAccess = Godot.FileAccess;

namespace CozySora;

/// <summary>Generated scene caches are invalidated by their map, shared components and shaders.</summary>
public static class CozySceneCache
{
    public static bool Enabled => DisplayServer.GetName() != "headless";

    public static string Signature(string mapFolder)
    {
        var paths = new List<string>();
        foreach (string folder in new[] { mapFolder, "res://shared", "res://shaders" }) Sources(folder, paths);
        paths.Sort(StringComparer.Ordinal);
        var source = new StringBuilder("cozy_generated_csharp_v1");
        foreach (string path in paths) source.Append(path).Append('\n').Append(FileAccess.GetFileAsString(path)).Append('\n');
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source.ToString()))).ToLowerInvariant()[..16];
    }

    private static void Sources(string folder, List<string> paths)
    {
        foreach (string file in DirAccess.GetFilesAt(folder))
            if (file.GetExtension() is "cs" or "gdshader" or "gdshaderinc" or "tres" or "tscn")
                paths.Add(folder.PathJoin(file));
        foreach (string directory in DirAccess.GetDirectoriesAt(folder)) Sources(folder.PathJoin(directory), paths);
    }

    public static Error Save(Node root, string path)
    {
        // The headless dummy renderer does not retain per-instance MultiMesh
        // transform writes. Serializing those resources would erase native scenery.
        if (!Enabled)
        {
            GD.Print("Cozy Sora: skipping scene cache in headless mode.");
            return Error.Ok;
        }
        SetOwners(root, root);
        var scene = new PackedScene();
        var error = scene.Pack(root);
        return error == Error.Ok ? ResourceSaver.Save(scene, path) : error;
    }

    public static bool RestoreChildren(Node parent, string path)
    {
        if (!Enabled) return false;
        if (!FileAccess.FileExists(path)) return false;
        var scene = ResourceLoader.Load<PackedScene>(path);
        if (scene is null) return false;
        var branch = scene.Instantiate();
        foreach (Node child in branch.GetChildren())
        {
            child.Owner = null;
            SetOwners(child, null);
            branch.RemoveChild(child);
            parent.AddChild(child);
        }
        branch.Free();
        return true;
    }

    private static void SetOwners(Node node, Node? owner)
    {
        foreach (Node child in node.GetChildren())
        {
            child.Owner = owner;
            SetOwners(child, owner);
        }
    }
}
