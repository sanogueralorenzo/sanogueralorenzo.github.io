class_name CozySolidMaterials
extends RefCounted
## Per-owner palette cache; callers can safely specialize their own materials.
var _materials: Dictionary = {}


func color(hex: String) -> StandardMaterial3D:
	if _materials.has(hex):
		return _materials[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = 1
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[hex] = material
	return material
