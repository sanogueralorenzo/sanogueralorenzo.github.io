class_name CozySceneCache
extends RefCounted
## Only generated resources are cached. Source dependencies invalidate both maps
## when a shared component changes, without coupling one map to the other.


static func signature(map_folder: String) -> String:
	var paths: Array[String] = []
	for folder in [map_folder, "res://shared", "res://shaders"]:
		_sources(folder, paths)
	paths.sort()
	var source := "cozy_generated_v2"
	for path in paths:
		source += path + "\n" + FileAccess.get_file_as_string(path) + "\n"
	return source.sha256_text().substr(0, 16)


static func _sources(folder: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["gd", "gdshader", "gdshaderinc", "tres", "tscn"]:
			paths.append(folder.path_join(file))
	for directory in DirAccess.get_directories_at(folder):
		_sources(folder.path_join(directory), paths)


static func save(root: Node, path: String) -> Error:
	_set_owners(root, root)
	var scene := PackedScene.new()
	var error := scene.pack(root)
	if error != OK:
		return error
	return ResourceSaver.save(scene, path)


static func restore_children(parent: Node, path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var branch := scene.instantiate()
	for child in branch.get_children():
		child.owner = null
		_set_owners(child, null)
		branch.remove_child(child)
		parent.add_child(child)
	branch.free()
	return true


static func _set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners(child, owner)
