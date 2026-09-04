class_name CozyVegetation
extends Node3D
## Seeded procedural foliage for Cozy Sora.
## Leaf silhouettes, lobed card canopies and curved grass blades are generated here.

var _world: Node3D
class SeededRandom:
	extends RefCounted
	var state: int = 1
	var seed: int = 1:
		set(value):
			seed = value
			state = value & 0xffffffff
	func randf() -> float:
		state = (state + 1831565813) & 0xffffffff
		var mixed: int = ((state ^ (state >> 15)) * (1 | state)) & 0xffffffff
		mixed = ((mixed + (((mixed ^ (mixed >> 7)) * (61 | mixed)) & 0xffffffff)) ^ mixed) & 0xffffffff
		return float((mixed ^ (mixed >> 14)) & 0xffffffff) / 4294967296.0
	func randf_range(low: float, high: float) -> float:
		return low + (high - low) * self.randf()
	func randi_range(low: int, high: int) -> int:
		return low + floori(self.randf() * (high - low + 1))

var _rng := SeededRandom.new()
var _trees: Array[Dictionary] = []
var _bushes: Array[Dictionary] = []
var _placed: Array[Vector3] = []
var _tree_batches: Array = []
var _bush_batches: Array = []
var _leaf_textures: Array[Texture2D] = []
var _large_leaf_texture: Texture2D
var _pine_texture: Texture2D
var _flower_patch_center := Vector2(INF,INF)
var _cache_path := ""

func build(world: Node3D) -> void:
	_world = world
	var signature: String = (get_script().source_code + world.get_script().source_code).sha256_text().substr(0,16)
	_cache_path = "user://foliage_" + signature + ".scn"
	if FileAccess.file_exists(_cache_path):
		var cached: PackedScene = load(_cache_path)
		if cached:
			var branch: Node = cached.instantiate()
			for child in branch.get_children():
				_clear_cache_owners(child)
				branch.remove_child(child)
				add_child(child)
			branch.free()
			print("Vegetation restored from procedural cache")
			return
	_rng.seed = 777
	_leaf_textures = [_leaf_texture(11), _leaf_texture(23), _leaf_texture(37, true)]
	_pine_texture = _pine_needle_texture()
	for i in range(6):
		_trees.append(_tree_mesh(i + 1, i == 2 or i == 4))
		_tree_batches.append([])
		await get_tree().process_frame
	for i in range(7):
		_bushes.append(_bush_mesh(i))
		_bush_batches.append([])
		await get_tree().process_frame
	_landmark_foliage()
	_forest_distribution()
	var palette := [Color("4c7a3a"), Color("3f7a4a"), Color("3c7052"), Color("3f7a4a"), Color("3c7052"), Color("3f7a4a")]
	for i in range(6):
		var leaves := _foliage_material(_leaf_textures[i % 2], palette[i], 0.16)
		_batch(_trees[i].leaves, leaves, _tree_batches[i], "Tree crowns %s" % i)
		_batch(_trees[i].trunk, _bark_material(), _tree_batches[i], "Branching trunks %s" % i)
	for i in range(7):
		var colors := [Color("5a7d34"), Color("5a7d34"), Color("9a9a38"), Color("3d6e3c"), Color("6a9340"), Color("8a923c"), Color("6a9340")]
		_batch(_bushes[i].leaves, _foliage_material(_leaf_textures[2 if i >= 4 else i % 2], colors[i], 0.10), _bush_batches[i], "Hedges %s" % i)
	_world.load_progress.emit("Planting the meadows…",.72)
	await get_tree().process_frame
	await _grass_fields()
	_flowers()
	_rosettes()
	_world.load_progress.emit("Adding the last summer details…",.90)
	await get_tree().process_frame
	_area_flora()
	print("Vegetation: ", _placed.size(), " trees and shrubs, procedural grass and flowers")
	_own_cache_children(self)
	var scene := PackedScene.new()
	if scene.pack(self) == OK:
		ResourceSaver.save(scene,_cache_path)

func _own_cache_children(node: Node) -> void:
	for child in node.get_children():
		child.owner = self
		_own_cache_children(child)

func _unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()

func _coast(x: float) -> float:
	return -0.0022 * x * x + 0.00001 * x * x * x

func _tree_mesh(seed_value: int, tall: bool) -> Dictionary:
	var saved: int = _rng.state
	_rng.seed = seed_value
	var h: float = _rng.randf_range(7, 11) if tall else _rng.randf_range(4.5, 7.5)
	var radii := Vector3(_rng.randf_range(2.4, 4.2), _rng.randf_range(2, 3.4), _rng.randf_range(2.4, 4.2))
	var center := Vector3(0, h + radii.y * 0.35, 0)
	var leaves := _canopy(center, radii, _rng.randi_range(6, 9), _rng.randi_range(52, 69), 7, _rng.randf_range(1.2, 1.6), _rng.randf_range(0.9, 1.3), h * 0.5, h + radii.y * 1.6)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h: float = h + radii.y * 0.2
	var radius: float = _rng.randf_range(0.22, 0.36)
	_tapered_branch(trunk, Vector3.ZERO, Vector3(0, trunk_h, 0), radius, radius * 0.55, 9)
	for j in range(4):
		var end := Vector3(_rng.randf_range(-0.6, 0.6) * radii.x, h + radii.y * _rng.randf_range(0.1, 0.7), _rng.randf_range(-0.6, 0.6) * radii.z)
		_tapered_branch(trunk, Vector3(0, trunk_h, 0), end, radius * 0.36, radius * 0.16, 6)
	trunk.generate_normals()
	var result := {"leaves": leaves, "trunk": trunk.commit(), "radius": maxf(radii.x, radii.z) + 1}
	_rng.state = saved
	return result

func _bush_mesh(kind: int) -> Dictionary:
	var saved: int = _rng.state
	_rng.seed = [21,22,23,31,41,42,43][kind]
	var radii := Vector3(_rng.randf_range(1.2, 2.4), _rng.randf_range(0.9, 1.7), _rng.randf_range(1.2, 2.4)) if kind<3 else Vector3.ONE
	var clusters: int = 0
	var size: float = 0
	if kind == 3:
		radii = Vector3(1.6, 1.5, 1.6)
		clusters = 40
		size = 0.75
	elif kind >= 4:
		radii = [Vector3(2.6, 1.9, 2.4), Vector3(2.2, 2.3, 2.2), Vector3(3, 1.6, 2.6)][kind - 4]
		clusters = [70, 64, 76][kind - 4]
		size = [0.78, 0.72, 0.8][kind - 4]
	var lobes: int = _rng.randi_range(5,7)
	if kind<3:
		clusters = _rng.randi_range(18,27)
		size = _rng.randf_range(0.85,1.15)
	var leaves := _canopy(Vector3(0, radii.y * 0.75, 0), radii, lobes, clusters, 6, size, _rng.randf_range(0.55, 0.85), 0, radii.y * 2,"gold" if kind in [2,5] else ("cool" if kind==3 else "green"))
	_rng.state = saved
	return {"leaves": leaves, "radius": maxf(radii.x, radii.z)}

func _canopy(center: Vector3, radii: Vector3, lobes: int, clusters: int, cards: int, card_size: float, cluster_radius: float, sway_base: float, sway_top: float, tint_kind: String = "green") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers: Array[Vector3] = []
	for i in range(lobes):
		var phi: float = _rng.randf() * TAU
		var y: float = _rng.randf_range(-1, 1)
		centers.append(center + Vector3(sqrt(1 - y * y) * cos(phi), y, sqrt(1 - y * y) * sin(phi)) * radii * 0.7 + Vector3(0, radii.y * 0.1, 0))
	for i in range(clusters):
		var cluster: Vector3 = centers[_rng.randi_range(0, centers.size() - 1)] + _unit() * pow(_rng.randf(), 0.6) * cluster_radius * 1.6
		var tint: Color
		if tint_kind == "gold":
			tint = Color(_rng.randf_range(1.1,1.6),_rng.randf_range(1,1.25),_rng.randf_range(0.45,0.75))
		elif tint_kind == "cool":
			tint = Color(_rng.randf_range(0.7,1),_rng.randf_range(0.85,1.1),_rng.randf_range(0.85,1.15))
		else:
			tint = Color(_rng.randf_range(0.85,1.3),_rng.randf_range(0.9,1.15),_rng.randf_range(0.75,1.05))
		var shade: float = (0.72 + 0.28 * minf(1, ((cluster - center) / radii).length())) * _rng.randf_range(0.62, 1.34)
		var color: Color = tint * shade
		for j in range(cards):
			var p: Vector3 = cluster + _unit() * pow(_rng.randf(), 0.7) * cluster_radius
			var radial: Vector3 = ((p - center) / (radii * radii)).normalized()
			var outward: Vector3 = (p - cluster).normalized().lerp(radial, 0.72).normalized()
			var normal: Vector3 = (outward + Vector3(_rng.randf_range(-0.6,0.6),_rng.randf_range(-0.6,0.6),_rng.randf_range(-0.6,0.6))).normalized()
			if _rng.randf() < 0.25:
				normal = _unit()
			var basis := Basis(Quaternion(Vector3.BACK, normal)).rotated(normal, _rng.randf() * TAU)
			var size: float = card_size * _rng.randf_range(0.75, 1.25)
			var points := [Vector3(-0.5,-0.5,0),Vector3(0.5,-0.5,0),Vector3(0.5,0.5,0),Vector3(-0.5,0.5,0)]
			var uvs := [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
			var weights: Array[float] = []
			for corner in range(4):
				weights.append(clampf((p.y - sway_base) / (sway_top - sway_base), 0, 1) * _rng.randf_range(0.6, 1))
			for k in [0,2,1,0,3,2]:
				var vertex: Vector3 = p + basis * points[k] * size
				st.set_uv(uvs[k])
				st.set_normal(outward.lerp(((vertex-center)/(radii*radii)).normalized(),0.35).normalized())
				color.a = weights[k]
				st.set_color(color)
				st.add_vertex(vertex)
	return st.commit()

func _tapered_branch(st: SurfaceTool, start: Vector3, end: Vector3, radius: float, tip: float, segments: int) -> void:
	var direction: Vector3 = (end - start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var other: Vector3 = direction.cross(side).normalized()
	for i in range(segments):
		var a: float = float(i) / segments * TAU
		var b: float = float(i + 1) / segments * TAU
		var radial_a: Vector3 = side * cos(a) + other * sin(a)
		var radial_b: Vector3 = side * cos(b) + other * sin(b)
		var points := [start + radial_a * radius, start + radial_b * radius, end + radial_b * tip, end + radial_a * tip]
		for k in [0,2,1,0,3,2]:
			st.set_uv(Vector2(float(i) / segments, 0 if k < 2 else 1))
			st.add_vertex(points[k])

func _leaf_texture(seed_value: int, small: bool = false) -> Texture2D:
	var random := SeededRandom.new()
	random.seed = seed_value
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for pass_index in range(2):
		var count: int = (70 if small else 30) if pass_index == 0 else (154 if small else 48)
		for i in range(count):
			var angle: float = random.randf() * TAU
			var radius: float = sqrt(random.randf()) * (56 if pass_index == 0 else 77)
			var p := Vector2(128 + cos(angle) * radius, 128 + sin(angle) * radius * 0.9)
			var factor: float = 0.55 if small else 1
			var length: float = random.randf_range(40, 75) * factor
			var width: float = random.randf_range(22, 40) * factor
			var rotation: float = random.randf() * TAU
			var shade: float = random.randf_range(0.47,0.67) if pass_index == 0 else random.randf_range(0.63,1) - radius / 77 * 0.10
			_paint_leaf(image, p, length, width, rotation, shade, pass_index == 1)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _paint_leaf(image: Image, center: Vector2, length: float, width: float, angle: float, shade: float, outline: bool) -> void:
	var extent: int = ceili(length * 0.6 + width * 0.6)
	for y in range(maxi(0,int(center.y)-extent), mini(256,int(center.y)+extent+1)):
		for x in range(maxi(0,int(center.x)-extent), mini(256,int(center.x)+extent+1)):
			var p: Vector2 = (Vector2(x,y) - center).rotated(-angle)
			var v: float = p.y / (length * 0.5)
			if absf(v) >= 1:
				continue
			var half_width: float = width * 0.5 * pow(1 - v * v, 0.8)
			if absf(p.x) > half_width:
				continue
			var ink: float = shade - (0.27 if outline and absf(p.x) > half_width - 0.9 else 0)
			image.set_pixel(x,y,Color(ink,ink,ink,1))

func _foliage_material(texture: Texture2D, color: Color, wind: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/foliage.gdshader")
	material.set_shader_parameter("leaf_texture",texture)
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("wind_amplitude",wind)
	return material

func _bark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a3a2c")
	material.roughness = 1
	var image := Image.create(64,256,false,Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(64):
			var stripe: float = sin(x*1.3 + sin(y*0.025)*1.7) * 0.09 + sin(x*3.4+y*0.04)*0.055
			image.set_pixel(x,y,Color(0.82+stripe,0.78+stripe,0.72+stripe))
	image.generate_mipmaps()
	material.albedo_texture = ImageTexture.create_from_image(image)
	return material

func _batch(mesh: Mesh, material: Material, transforms: Array, label: String, range_end: float = 0) -> void:
	if transforms.is_empty():
		return
	var groups := {}
	for transform: Transform3D in transforms:
		var key := Vector2i(floori(transform.origin.x / 24), floori(transform.origin.z / 24))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(transform)
	for key: Vector2i in groups:
		var instances := MultiMeshInstance3D.new()
		instances.name = label
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = groups[key].size()
		var origin := Vector3(key.x * 24 + 12, 0, key.y * 24 + 12)
		for i in range(multimesh.instance_count):
			var transform: Transform3D = groups[key][i]
			transform.origin -= origin
			multimesh.set_instance_transform(i, transform)
		instances.multimesh = multimesh
		instances.material_override = material
		instances.position = origin
		instances.visibility_range_end = range_end
		instances.visibility_range_end_margin = 10 if range_end > 0 else 0
		add_child(instances)
		if label == "Wind grass":
			instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shadow := MultiMeshInstance3D.new()
			shadow.name = "Nearby grass shadows"
			shadow.multimesh = multimesh
			shadow.material_override = material
			shadow.position = origin
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shadow.visibility_range_end = 28
			shadow.visibility_range_end_margin = 6
			add_child(shadow)

func _clear_of_other(x: float, z: float, radius: float) -> bool:
	for p: Vector3 in _placed:
		if Vector2(p.x-x,p.z-z).length_squared() < pow(p.y+radius,2)*0.22:
			return false
	return true

func _plant_tree(x: float, z: float, scale_value: float, kind: int, crowd: float = 1, force: bool = false, special_scale: Vector3 = Vector3.ZERO, yaw: float = -1) -> void:
	var radius: float = _trees[kind].radius * scale_value
	if not force:
		if _world.surface_at(x,z)!="grass" or _world.excluded(x,z) or _world.road_info(x,z).d < 6.5+scale_value:
			return
		if x > -11.5 and x < -1.3 and z-_coast(x)>-11 and z-_coast(x)<9.5:
			return
		if not _clear_of_other(x,z,radius*crowd):
			return
	var rotation: float = _rng.randf()*TAU if yaw < 0 else yaw
	var tilt := Vector3.ZERO if force else Vector3(_rng.randf_range(-0.04,0.04),0,_rng.randf_range(-0.04,0.04))
	var size := (Vector3.ONE*scale_value if force else Vector3(scale_value*_rng.randf_range(0.9,1.1),scale_value,scale_value*_rng.randf_range(0.9,1.1))) if special_scale == Vector3.ZERO else special_scale
	var transform := Transform3D((Basis(Vector3.UP,rotation)*Basis.from_euler(tilt)).scaled(size),Vector3(x,_world.height_at(x,z)-0.15,z))
	_tree_batches[kind].append(transform)
	_placed.append(Vector3(x,radius,z))
	if absf(x)<110 and z<100:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.3*scale_value + 0.15
		cylinder.height = 3*scale_value
		shape.shape = cylinder
		shape.position.y = cylinder.height*0.5
		body.position = transform.origin
		body.add_child(shape)
		add_child(body)

func _plant_bush(x: float, z: float, scale_value: float, kind: int, crowd: float = 0.6, force: bool = false, special_scale: Vector3 = Vector3.ZERO, yaw: float = -1) -> void:
	var radius: float = _bushes[kind].radius * scale_value
	var local_z: float = z-_coast(x)
	var layby: bool = x>-9.6 and x<-3.2 and local_z>-9.1 and local_z<7.6
	if not force and (_world.surface_at(x,z)!="grass" or _world.excluded(x,z,-2.8) or layby or _world.road_info(x,z).d < 5.2 or not _clear_of_other(x,z,radius*crowd)):
		return
	var rotation: float = _rng.randf()*TAU if yaw<0 else yaw
	var size := Vector3(scale_value,scale_value*_rng.randf_range(0.85,1.15),scale_value) if special_scale == Vector3.ZERO else special_scale
	# Keep roadside wayfinding boards above nearby shrubs, preserving each seed's planting footprint.
	for sign_position in [Vector2(-8.75,3.2),Vector2(-1,-17.05),Vector2(40,-17.1+_coast(40)),Vector2(-12.5,-17.2+_coast(-12.5))]:
		if Vector2(x,z).distance_to(sign_position)<radius+.7:
			var canopy_height:float=_bushes[kind].leaves.get_aabb().end.y
			size.y=minf(size.y,.9/maxf(.1,canopy_height))
	_bush_batches[kind].append(Transform3D(Basis(Vector3.UP,rotation).scaled(size),Vector3(x,_world.height_at(x,z)-0.2,z)))
	_placed.append(Vector3(x,radius*0.8,z))

func _landmark_foliage() -> void:
	_plant_tree(-1.1,-4,1.45,1,1,true,Vector3(1.45,1.2,1.45),1.2)
	_placed[-1] = Vector3(-1.1,4,-4)
	_plant_tree(-11.5,-6.5,1,3,1,true,Vector3(1,0.85,1),2.1)
	_placed[-1] = Vector3(-11.5,0.6,-6.5)
	_plant_bush(-11,-5.4,1.3,6,1,true,Vector3(1.3,1.65,1.2),0.9)
	_placed[-1] = Vector3(-11,2.4,-5.4)
	_plant_bush(-10.1,-7,0.9,5,1,true,Vector3(0.9,1,0.9),2.4)
	_placed.remove_at(_placed.size()-1)
	_plant_tree(-15.5,-5,1.5,4,1,true,Vector3.ONE*1.5,0.8)
	_placed[-1] = Vector3(-15.5,0.6,-5)
	_plant_tree(-11,1.5,1.7,2,1,true,Vector3.ONE*1.7,2.1)
	_placed[-1] = Vector3(-11,0.6,1.5)
	_plant_tree(-7,-18.2,2,3,1,true,Vector3(2.3,1.15,1.7),0)
	_placed[-1] = Vector3(-7,0.6,-18.2)
	for p in [Vector2(-13.5,-18.4),Vector2(-16.5,-18.6),Vector2(-19.5,-18.8)]:
		_plant_bush(p.x,p.y,1.3,3,0.1)
	for row in [[-8,-17.8,1.2,6,0.4],[-5,-17.95,1,5,1.7],[-1.8,-17.85,1.15,6,2.6],[1.6,-18,0.95,4,0.9]]:
		_plant_bush(row[0],row[1]+_coast(row[0]),row[2],row[3],1,true,Vector3.ONE*row[2],row[4])
	for row in [[34,-19.1,1.6,0],[40,-19.3,1.8,2],[46,-19,1.5,0],[56,-23.2,1.5,0],[58.5,-23,1,5],[60.5,-23.6,1.25,1],[63,-23.5,0.95,0],[65.5,-23.3,1.5,5],[70,-23.6,1.3,3]]:
		_plant_tree(row[0],row[1]+(_coast(row[0]) if row[0]<50 else 0),row[2],row[3],1,true)
	for i in range(6):
		var x: float = 12+i*2.8+_rng.randf()*1.2
		_plant_bush(x,-18.6+_rng.randf_range(-0.15,0.15)+_coast(x),_rng.randf_range(1.3,1.8),3,1,true)
	for i in range(26):
		var t: float = float(i)/26
		_plant_bush(-10.1-_rng.randf()*1.4-t*3,8-t*24+_rng.randf_range(-0.75,0.75),_rng.randf_range(0.95,1.3),5 if i in [5,9,13] else (4 if i%2 else 6),0.22)
	for i in range(14):
		_plant_tree(-12.2-_rng.randf()*4,-6+i*1.7+_rng.randf_range(-1,1),_rng.randf_range(1.3,1.9),[2,4,0,1][i%4],0.25)
	for i in range(10):
		_plant_tree(-17-_rng.randf()*5,-7+i*2.4+_rng.randf_range(-1,1),_rng.randf_range(1.6,2.3),[4,2,5,3][i%4],0.2)
	_plant_bush(-0.6,0.4,1.2,3,0.1)
	for row in [[3,-5.9,1.3],[7.5,-5.5,1.5],[12.5,-5.2,1.2],[17,-4.6,1.4]]:
		_plant_bush(row[0],row[1],row[2],3,0.1)
	for i in range(18):
		_plant_bush(-0.8+_rng.randf()*1.8+(2.5 if i>11 else 0),-2.5+i*0.75+_rng.randf_range(-0.6,0.6),_rng.randf_range(1.15,1.65),3,0.3)
	for i in range(24):
		_plant_bush(_rng.randf_range(-1,11),_rng.randf_range(4,13),_rng.randf_range(1,1.7),3 if i%3==0 else i%2)

func _keep_clearing(x: float, z: float) -> bool:
	return (x < -68 and absf(z-25)<13+maxf(0,-90-x)*0.6) or (x>-68 and x<-56 and z>37 and z<48) or (x>-67 and x<-50 and z>48 and z<63.5)

func _forest_distribution() -> void:
	for i in range(1500):
		var x: float = -76-pow(_rng.randf(),0.8)*50
		var z: float = -40+_rng.randf()*140
		if not _keep_clearing(x,z):
			_plant_tree(x,z,_rng.randf_range(0.9,1.7),_rng.randi_range(0,5))
	for i in range(1800):
		var x: float = _rng.randf_range(-120,120)
		var z: float = 86+pow(_rng.randf(),0.8)*50
		var gap: bool = x>-2 and x<56 and z<135
		if not (gap and (z<112 or _rng.randf()<0.8)):
			_plant_tree(x,z,_rng.randf_range(0.4,0.65) if gap else _rng.randf_range(1,1.9),_rng.randi_range(0,5))
	for i in range(700):
		var x: float = 100+pow(_rng.randf(),0.8)*45
		var z: float = _rng.randf_range(-30,90)
		var gap: bool = z>-12 and z<90
		if not ((gap and x<110) or (gap and x>=120 and _rng.randf()<0.75)):
			_plant_tree(x,z,_rng.randf_range(0.3,0.5) if gap else _rng.randf_range(0.9,1.7),_rng.randi_range(0,5))
	for i in range(260):
		_plant_tree(_rng.randf_range(30,66),_rng.randf_range(79,89),_rng.randf_range(0.8,1.2),_rng.randi_range(0,5),0.3)
	for i in range(50):
		_plant_tree(_rng.randf_range(60,104),_rng.randf_range(47,55),_rng.randf_range(0.35,0.5),_rng.randi_range(0,5),0.3)
	for i in range(120):
		_plant_tree(_rng.randf_range(60,104),_rng.randf_range(-14,-8),_rng.randf_range(1,1.7),_rng.randi_range(0,5),0.3)
	for i in range(200):
		var x: float = _rng.randf_range(-76,-58)
		var z: float = _rng.randf_range(-10,50)
		if not _keep_clearing(x,z):
			_plant_tree(x,z,_rng.randf_range(1,1.8),_rng.randi_range(0,5),0.3)
	for i in range(900):
		var x: float = _rng.randf_range(-75,75)
		var z: float = _rng.randf_range(-4,88)
		var shrine_distance: float = Vector2(x,z-30).length()
		if shrine_distance<23 or (z>4 and z<26 and x>-16 and x<12) or (z>70 and x>6 and x<50) or _keep_clearing(x,z):
			continue
		if _rng.randf() < (0.35 if shrine_distance<27 else 0.55) or (z>56 and z<79 and x>44 and x<80):
			continue
		_plant_tree(x,z,_rng.randf_range(0.35,0.5) if z>42 and z<57 and x>56 else _rng.randf_range(0.8,1.6),_rng.randi_range(0,5))
	for i in range(400):
		var x: float = _rng.randf_range(-75,75)
		var z: float = _rng.randf_range(-4,88)
		if _keep_clearing(x,z) or (z>4 and z<26 and x>-16 and x<12) or (z>70 and x>6 and x<50) or (z>56 and z<78 and x>34 and x<66):
			continue
		_plant_bush(x,z,_rng.randf_range(0.9,1.9),_rng.randi_range(0,2))
	for i in range(40):
		_plant_tree(_rng.randf_range(-75,-37),_rng.randf_range(-21.5,-18.5),_rng.randf_range(0.8,1.4),_rng.randi_range(0,5))

func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(3):
		var angle: float = blade*TAU/3+_rng.randf()*0.8
		var basis := Basis(Vector3.UP,angle)
		var width: float = _rng.randf_range(0.1,0.15)
		var bend: float = _rng.randf_range(0.2,0.6)
		var offset := Vector3(_rng.randf_range(-0.06,0.06),0,_rng.randf_range(-0.06,0.06))
		for segment in range(4):
			for k in [0,2,1,1,2,3]:
				var t: float = float(segment+k/2)/4
				var sign_x: float = -1 if k%2==0 else 1
				st.set_uv(Vector2(0 if sign_x<0 else 1,t))
				st.set_normal(basis*Vector3(0,0.3,1).normalized())
				st.set_color(Color.WHITE)
				st.add_vertex(offset+basis*Vector3(sign_x*width*(1-t*t)*0.5,t,bend*t*t))
	return st.commit()

func _grass_fields() -> void:
	_rng.seed = 4242
	var mesh := _grass_mesh()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/grass.gdshader")
	var transforms: Array = []
	var samples := {}
	var attempts: int = 0
	# Grow up to 380,000 clumps. Spatial batches let Godot cull
	# fields behind the camera and beyond the atmospheric distance.
	while transforms.size()<380000 and attempts<1140000:
		attempts += 1
		if attempts%10000 == 0:
			await get_tree().process_frame
		var x: float = _rng.randf_range(-125,125)
		var z: float = _rng.randf_range(-30,100)
		var cell := Vector2i(floori(x*2),floori(z*2))
		if not samples.has(cell):
			var sx: float = cell.x*0.5+0.25
			var sz: float = cell.y*0.5+0.25
			samples[cell] = Vector2(-1 if _world.excluded(sx,sz,0.6) else 1,_world.height_at(sx,sz))
		var sample: Vector2 = samples[cell]
		if sample.x<0 or z-_coast(x)<-27:
			continue
		if x>-9 and x<-3.8 and z-_coast(x)>-8.5 and z-_coast(x)<7:
			continue
		var distance: float = Vector2(x,z).length()
		var density: float = 0.25 if z>90 or x<-80 or x>105 else (1.0 if distance<25 else 0.6)
		if _rng.randf()>density or sample.y<-1.5:
			continue
		var patch: float = 0.5+0.25*sin(x*0.12+40)*cos(z*0.12+9)+0.15*sin(x*0.27+z*0.18)
		if patch<0.36 and _rng.randf()<0.6:
			continue
		var size: float = minf(1.05,0.45+patch*0.7+_rng.randf()*0.3)
		if z<-4 and z-_coast(x)<-16.5:
			size *= 0.35
		if x<-9 and x>-11.6 and z-_coast(x)>-8.5 and z<8:
			size *= 0.3
		size *= (0.9+(1-minf(1,distance/40))*0.3)*(1.35 if density<1 else 1)
		var ground: float = _world.height_at(x,z) if distance<25 else sample.y
		transforms.append(Transform3D(Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(size*_rng.randf_range(0.8,1.2),size,size*_rng.randf_range(0.8,1.2))),Vector3(x,ground-0.02,z)))
	for i in range(250):
		var seaside: bool = _rng.randf()<0.3
		var x: float = _rng.randf_range(-2.6,-1.8) if seaside else _rng.randf_range(-3.7,-2.4)
		var z: float = _rng.randf_range(-8,-3.6) if seaside else _rng.randf_range(-3.6,1.4)
		var size: float = _rng.randf_range(0.9,1.3) if seaside else _rng.randf_range(1,1.4)
		transforms.append(Transform3D(Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(x,_world.height_at(x,z)-0.02,z)))
	_batch(mesh,material,transforms,"Wind grass",88)

func _rosettes(rows: Array = [], plant_color: Color = Color("2f6a36"), second_color: Color = Color.TRANSPARENT) -> void:
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_paint_leaf(image,Vector2(128,130),216,184,0,0.71,true)
	for y in range(35,239):
		for x in range(125,131):
			image.set_pixel(x,y,Color(0.87,0.87,0.87,1))
	for level in range(5):
		for side in [-1,1]:
			for step in range(67):
				var x: int = 128+step*side
				var y: int = 213-level*34-step/2
				for thickness in range(-1,2):
					if image.get_pixel(x,y+thickness).a>0.5:
						image.set_pixel(x,y+thickness,Color(0.87,0.87,0.87,1))
	image.generate_mipmaps()
	_large_leaf_texture = ImageTexture.create_from_image(image)
	var material := _foliage_material(_large_leaf_texture,plant_color,0.05)
	material.set_shader_parameter("near_fade",0.9)
	material.set_shader_parameter("gradient_bottom",Vector3(0.85,0.95,1.0))
	material.set_shader_parameter("gradient_top",Vector3(1.1,1.05,0.8))
	if second_color.a>0:
		var base_linear: Color = plant_color.srgb_to_linear()
		var tip_linear: Color = second_color.srgb_to_linear()
		material.set_shader_parameter("gradient_top",Vector3(minf(4,tip_linear.r/maxf(base_linear.r,0.001)),minf(4,tip_linear.g/maxf(base_linear.g,0.001)),minf(4,tip_linear.b/maxf(base_linear.b,0.001))))
	if rows.is_empty():
		rows = [[-4.3,-3.4,1.5,3],[-4.9,-2.6,1.3,5],[-3.7,-4.3,1.45,7],[-3.2,-5.4,1.3,11],[-4,-2.3,1.1,13],[-4.6,-4.4,1.2,17],[-3,-3,1.4,19]]
	for row in rows:
		_rng.seed = row[3]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count: int = _rng.randi_range(7,11)
		for i in range(count):
			var angle: float = float(i)/count*TAU+_rng.randf()*0.6
			var lean: float = _rng.randf_range(0.5,1.2)
			var size: float = _rng.randf_range(0.7,1.2)*row[2]
			var basis := Basis(Vector3.UP,-angle)*Basis(Vector3.RIGHT,-lean)
			for segment in range(2):
				for k in [0,2,1,1,2,3]:
					var v: float = float(segment+k/2)/2
					var u: float = k%2
					st.set_uv(Vector2(u,1-v))
					st.set_color(Color(1,1,1,v*0.9))
					st.set_normal((basis*Vector3(0,0.5,1)).normalized())
					st.add_vertex(basis*Vector3((u-0.5)*size,v*size*1.15,size*0.09*sin(v*PI))+Vector3(cos(angle)*0.15,0.1,-sin(angle)*0.15))
		var instance := MeshInstance3D.new()
		instance.name = "Broad dock leaves"
		instance.mesh = st.commit()
		instance.material_override = material
		var lift: float = row[4] if row.size()>4 else 0
		var tiers: int = row[5] if row.size()>5 else 1
		instance.position = Vector3(row[0],_world.height_at(row[0],row[1])-0.05+lift,row[1])
		add_child(instance)
		for tier in range(1,tiers):
			var lower := instance.duplicate() as MeshInstance3D
			lower.scale = Vector3.ONE*pow(0.82,tier)
			lower.position.y -= lift*float(tier)/tiers
			add_child(lower)
		if lift>0.1:
			_world.cylinder(self,Vector3(row[0],_world.height_at(row[0],row[1])+lift*0.5,row[1]),0.05,0.03,lift,_world.mat("3a5936"))

func _flower_texture(color: Color, seed_value: int) -> Texture2D:
	var random := SeededRandom.new()
	random.seed = seed_value
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in range(5):
		var x: int = random.randi_range(40,216)
		var y: int = random.randi_range(40,128)
		for sy in range(y,256):
			for sx in range(-2,3):
				image.set_pixel(clampi(x+sx+int(sin(sy*0.025+i)*5),0,255),sy,Color("5b7c32"))
		for petal in range(random.randi_range(5,9)):
			var px: int = x+random.randi_range(-14,14)
			var py: int = y+random.randi_range(-12,12)
			var radius: int = random.randi_range(5,9)
			for dy in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					if dx*dx+dy*dy<=radius*radius:
						image.set_pixel(px+dx,py+dy,color)
		for dy in range(-3,4):
			for dx in range(-3,4):
				if dx*dx+dy*dy<10:
					image.set_pixel(x+dx,y+dy,Color("ffd54a"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _flowers() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0,PI*0.5]:
		var basis := Basis(Vector3.UP,angle)
		for k in [0,2,1,0,3,2]:
			var uv: Vector2 = [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][k]
			st.set_uv(uv)
			st.set_normal(Vector3.UP)
			st.set_color(Color(1,1,1,1-uv.y))
			st.add_vertex(basis*Vector3((uv.x-0.5)*0.6,(1-uv.y)*0.7,0))
	var mesh := st.commit()
	var sets := [
		{"color":Color("d6566e"),"patches":[[-3.3,-4.6,0.7,30],[-3.2,-6.3,0.7,25],[-3.5,-7.75,0.6,24],[-1.4,-7.3,0.7,26],[1.8,-7.15,0.8,30],[5.4,-6.95,0.7,22]]},
		{"color":Color("de7288"),"patches":[[-3.3,-3.9,0.5,10],[-2.6,-7.95,0.45,9],[0.2,-7.4,0.5,10],[3.7,-7.2,0.5,9]]},
		{"color":Color("ee7a2a"),"patches":[[-9.9,1.5,0.7,30],[-9.9,-2.5,0.7,30],[-9.9,-6,0.7,25]]},
		{"color":Color("f2cf4a"),"patches":[[-9.9,4.5,0.7,20],[-9.9,-4.2,0.6,15]]},
		{"color":Color("f6f2e8"),"patches":[[20,-18,3,60],[-25,-18.5,3,50]]}]
	for i in range(sets.size()):
		var transforms: Array = []
		for patch in sets[i].patches:
			for j in range(patch[3]):
				var angle: float = _rng.randf()*TAU
				var radius: float = sqrt(_rng.randf())*patch[2]
				var x: float = patch[0]+cos(angle)*radius
				var z: float = patch[1]+sin(angle)*radius
				var size: float = _rng.randf_range(0.8,1.3) if i<2 else _rng.randf_range(0.9,1.6)
				transforms.append(Transform3D(Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(x,_world.height_at(x,z)-0.02,z)))
		var material := _foliage_material(_flower_texture(sets[i].color,9+i),Color.WHITE,0.16)
		material.set_shader_parameter("color_texture",true)
		material.set_shader_parameter("near_fade",0.3)
		_batch(mesh,material,transforms,"Wildflower patches",90)

func _broad_tree(x: float, z: float, height: float, radius: float, seed_value: int, options: Dictionary = {}) -> void:
	_rng.seed = seed_value
	var canopy_material := _foliage_material(_leaf_textures[0],Color.hex((int(options.get("color",4880954))<<8)|255),0.14)
	canopy_material.set_shader_parameter("band_lift",options.get("leaf_lift",0.1))
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends: Array[Vector3] = []
	for i in range(4):
		ends.append(Vector3(_rng.randf_range(-0.65,0.65)*radius,height+1+_rng.randf()*2.5,_rng.randf_range(-0.65,0.65)*radius))
	_tapered_branch(trunk,Vector3.ZERO,Vector3(0,height+0.5,0),0.42,0.23,9)
	for end in ends:
		_tapered_branch(trunk,Vector3(0,height+0.5,0),end,0.15,0.065,6)
	trunk.generate_normals()
	var stem := MeshInstance3D.new()
	stem.mesh = trunk.commit()
	stem.material_override = _bark_material()
	stem.material_override.albedo_color = Color.hex((int(options.get("bark",6969416))<<8)|255)
	stem.position = Vector3(x,_world.height_at(x,z)-0.2,z)
	add_child(stem)
	var crown := MeshInstance3D.new()
	crown.name = "Area broadleaf %s %s" % [x,z]
	crown.mesh = _canopy(Vector3(0,height+radius*0.55,0),Vector3(radius,radius*0.72,radius),8,options.get("clusters",110),7,options.get("card_size",1.6),options.get("cluster_radius",1.2),height*0.5,height+radius*1.6)
	crown.material_override = canopy_material
	crown.position = stem.position
	if not options.get("shadow",true):
		crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crown)

func _pine_tree(x: float,z: float,height: float,seed_value: int) -> void:
	_rng.seed = seed_value
	var ground: float = _world.height_at(x,z)-0.2
	var lean: float = _rng.randf_range(-0.125,0.125)
	var trunk: MeshInstance3D = _world.cylinder(self,Vector3(x-sin(lean)*height*0.5,ground+height*0.5,z),0.42,0.16,height,_world.mat("8f6a58"))
	trunk.rotation.z = lean
	var count: int = 3+int(_rng.randf()<0.5)
	var phase: float = _rng.randf()*TAU
	for i in range(count):
		var fraction: float = float(i)/(count-1)
		var h: float = height*(0.5+fraction*0.5)
		var spread: float = height*0.12*(1-fraction)
		var angle: float = phase+i*2.2+_rng.randf_range(-0.4,0.4)
		var center := Vector3(cos(angle)*spread-sin(lean)*h,h,sin(angle)*spread)
		var radius: float = 0.34*height*(1-0.5*fraction)+_rng.randf()*0.5
		var mesh := _pine_tier(center,radius,height)
		var crown := MeshInstance3D.new()
		crown.name = "Japanese pine tiers"
		crown.mesh = mesh
		crown.material_override = _foliage_material(_pine_texture,Color("35603a"),0.06)
		crown.material_override.set_shader_parameter("band_lift",0.08)
		crown.position = Vector3(x,ground,z)
		add_child(crown)
		_world.beam(self,Vector3(x-sin(lean)*h*0.8,ground+h*0.8,z),Vector3(x,ground,z)+center,0.11,_world.mat("8f6a58"))
		for branch in [-1,1]:
			var branch_angle: float = angle+branch*1.9+_rng.randf_range(-0.4,0.4)
			_world.beam(self,Vector3(x,ground,z)+center,Vector3(x,ground,z)+center+Vector3(cos(branch_angle)*radius*0.7,0.15,sin(branch_angle)*radius*0.7),0.065,_world.mat("8f6a58"))

func _pine_tier(center: Vector3,radius: float,tree_height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(ceili(radius*radius*7)+12):
		var angle: float = _rng.randf()*TAU
		var distance: float = sqrt(_rng.randf())*radius
		var fraction: float = distance/radius
		var p := center+Vector3(cos(angle)*distance,0.14*radius*(1-fraction*fraction)+_rng.randf_range(-0.2,0.2),sin(angle)*distance)
		var size: float = _rng.randf_range(1,1.5)
		var pitch: float = 0.35+fraction*0.55+_rng.randf_range(-0.2,0.2)
		var basis := Basis(Vector3.UP,PI*0.5-angle)*Basis(Vector3.RIGHT,-(PI*0.5-pitch))*Basis(Vector3.BACK,_rng.randf_range(-0.4,0.4))
		var normal := Vector3(cos(angle)*0.6,1,sin(angle)*0.6).normalized()
		var shade: float = _rng.randf_range(0.72,1.12)*(0.78+0.22*fraction)
		var color := Color(shade*0.9,shade,shade*0.95,0.3+center.y/tree_height*0.35+0.25*fraction)
		for k in [0,2,1,0,3,2]:
			var uv: Vector2 = [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][k]
			st.set_uv(uv)
			st.set_normal(normal)
			st.set_color(color)
			st.add_vertex(p+basis*Vector3((uv.x-0.5)*size,(0.5-uv.y)*size*0.8,0))
	return st.commit()

func _pine_needle_texture() -> Texture2D:
	var random := SeededRandom.new()
	random.seed = 79
	var image := Image.create(512,512,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for cluster in range(70):
		var angle: float = random.randf()*TAU
		var radius: float = sqrt(random.randf())*153.6
		var center := Vector2(256+cos(angle)*radius,256+sin(angle)*radius)
		var shade: float = (120+floorf(random.randf()*110)-floorf(radius/153.6*30))/255
		var count: int = random.randi_range(9,14)
		var direction: float = random.randf()*TAU
		for needle in range(count):
			var theta: float = direction+(float(needle)/count-0.5)*2.2
			var length: float = random.randf_range(26,56)
			_paint_stroke(image,center,center+Vector2(cos(theta),sin(theta))*length,3,Color(shade,shade,shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _paint_disc(image: Image,center: Vector2,radius: float,color: Color) -> void:
	for y in range(maxi(0,floori(center.y-radius)),mini(image.get_height(),ceili(center.y+radius)+1)):
		for x in range(maxi(0,floori(center.x-radius)),mini(image.get_width(),ceili(center.x+radius)+1)):
			if Vector2(x,y).distance_squared_to(center)<=radius*radius:
				image.set_pixel(x,y,image.get_pixel(x,y).blend(color))

func _paint_stroke(image: Image,start: Vector2,end: Vector2,width: float,color: Color) -> void:
	var steps: int = maxi(1,ceili(start.distance_to(end)))
	for i in range(steps+1):
		_paint_disc(image,start.lerp(end,float(i)/steps),width*0.5,color)

func _paint_ellipse(image: Image,center: Vector2,radii: Vector2,color: Color) -> void:
	for y in range(maxi(0,floori(center.y-radii.y)),mini(image.get_height(),ceili(center.y+radii.y)+1)):
		for x in range(maxi(0,floori(center.x-radii.x)),mini(image.get_width(),ceili(center.x+radii.x)+1)):
			if ((Vector2(x,y)-center)/radii).length_squared()<=1:
				image.set_pixel(x,y,image.get_pixel(x,y).blend(color))

func _meadow(rect: Rect2, density: float, height: float, shrine: bool = false, options: Dictionary = {}) -> void:
	_rng.seed = floori(rect.position.x*3+rect.end.y*5)+7
	var mesh := _grass_mesh()
	var transforms: Array = []
	var amount: int = int(rect.size.x*rect.size.y*density)
	for i in range(amount):
		var x: float = _rng.randf_range(rect.position.x,rect.end.x)
		var z: float = _rng.randf_range(rect.position.y,rect.end.y)
		if not options.get("force",false) and _world.surface_at(x,z) not in ["grass","hardpack"]:
			continue
		if shrine and (_shrine_plant_skip(x,z) or absf(x-_shrine_path(z))<0.45):
			continue
		if not shrine and _world.road_info(x,z).d<4.5:
			continue
		var yaw: float = _rng.randf()*TAU
		var seed_head: bool = _rng.randf()<(0.26 if shrine else options.get("seed_heads",0))
		var scale_value: float = height*_rng.randf_range(0.75,1.25)*(1.45 if seed_head else 1)
		if shrine:
			scale_value *= 1-0.65*clampf((z-16.5)/2,0,1)
		var width: float = scale_value*(0.55 if seed_head else 1.2*options.get("width",1))
		transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(width,scale_value,width)),Vector3(x,_world.height_at(x,z)-0.02,z)))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/grass.gdshader")
	material.set_shader_parameter("grass_base",options.get("base",Vector3(0.12,0.27,0.22) if shrine else Vector3(0.2,0.32,0.12)))
	material.set_shader_parameter("grass_mid",options.get("mid",Vector3(0.27,0.43,0.19) if shrine else Vector3(0.42,0.55,0.2)))
	material.set_shader_parameter("grass_tip",options.get("tip",Vector3(0.43,0.55,0.24) if shrine else Vector3(0.72,0.76,0.3)))
	material.set_shader_parameter("band_lift",0.05)
	_batch(mesh,material,transforms,"Area meadow",90)

func _shrine_path(z: float) -> float:
	var points := [Vector2(-3.2,21.5),Vector2(-5.5,20.5),Vector2(-7.5,18.5),Vector2(-9,15),Vector2(-9.5,12),Vector2(-9,9),Vector2(-8.5,6)]
	for i in range(1,points.size()):
		if z<=points[i-1].y and z>=points[i].y:
			return lerpf(points[i-1].x,points[i].x,(points[i-1].y-z)/(points[i-1].y-points[i].y))
	return 99

func _shrine_plant_skip(x: float,z: float) -> bool:
	return Vector2(x+4.3,z-14.5).length()<2 or (absf(x-0.5)<4.6 and z>19.6)

func _shrine_flowers(center: Vector2, radius: float, count: int, color: Color, seed_value: int, scale_value: float = 1) -> void:
	if center != _flower_patch_center:
		_rng.seed = floori(center.x*11+center.y*3)+55
		_flower_patch_center = center
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0,PI*0.5]:
		var basis := Basis(Vector3.UP,angle)
		for segment in range(4):
			for k in [0,2,1,1,2,3]:
				var v: float = float(segment+k/2)/4
				var u: float = k%2
				st.set_uv(Vector2(u,1-v))
				st.set_normal(Vector3.UP)
				st.set_color(Color(1,1,1,v))
				st.add_vertex(basis*Vector3((u-0.5)*0.5,v*1.4,0))
	var mesh := st.commit()
	var transforms: Array = []
	for i in range(count):
		var angle: float = _rng.randf()*TAU
		var distance: float = sqrt(_rng.randf())*radius
		var p: Vector2 = center+Vector2(cos(angle),sin(angle))*distance
		if _shrine_plant_skip(p.x,p.y) or absf(p.x-_shrine_path(p.y))<0.9:
			continue
		var size: float = scale_value*_rng.randf_range(0.75,1.25)*(1-0.65*clampf((p.y-16.5)/2,0,1))
		var pos := Vector3(p.x,_world.height_at(p.x,p.y)-0.02-_rng.randf()*0.3*size,p.y)
		var rotation: float = _rng.randf()*PI
		transforms.append(Transform3D(Basis(Vector3.UP,rotation).scaled(Vector3(size*_rng.randf_range(0.85,1.15),size,size*_rng.randf_range(0.85,1.15))),pos))
	var kind: String = "aster" if color.b>color.r else ("red" if color.g<0.5 else "buttercup")
	var material := _foliage_material(_shrine_flower_texture(kind,seed_value),Color.WHITE,0.2)
	material.set_shader_parameter("color_texture",true)
	material.set_shader_parameter("band_lift",0.3)
	material.set_shader_parameter("band_scale",0.45)
	material.set_shader_parameter("near_fade",0.4)
	_batch(mesh,material,transforms,"Shrine wildflowers",90)

func _shrine_flower_texture(kind: String,seed_value: int) -> Texture2D:
	var random := SeededRandom.new()
	random.seed = seed_value
	var image := Image.create(128,384,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if kind == "aster":
		for i in range(2+int(random.randf()<0.5)):
			var center := Vector2(40+(i%2)*48+random.randf_range(-6,6),40+i*66+random.randf()*24)
			var radius: float = random.randf_range(31,36)
			var petals: int = random.randi_range(12,14)
			var phase: float = random.randf()*PI
			for petal in range(petals):
				var angle: float = float(petal)/petals*TAU+phase
				var length: float = radius*random.randf_range(0.88,1.02)
				_paint_stroke(image,center,center+Vector2(cos(angle),sin(angle))*length,12,Color("a894d2"))
			_paint_disc(image,center,radius*0.62,Color("a894d2"))
			_paint_disc(image,center,11,Color("e6bc4e"))
		_paint_ellipse(image,Vector2(random.randf_range(40,88),random.randf_range(210,260)),Vector2(10,14),Color("9a86c6"))
	elif kind == "buttercup":
		for stalk in range(2):
			var x: float = 34+stalk*60+random.randf_range(-7,7)
			var y: float = random.randf_range(44,114)
			for bloom in range(2+int(random.randf()<0.5)):
				_paint_disc(image,Vector2(x+random.randf_range(-11,11),y+bloom*random.randf_range(36,48)-4),random.randf_range(21,24),Color("eeae36"))
	else:
		for stalk in range(2):
			var center := Vector2(32+stalk*64+random.randf_range(-8,8),random.randf_range(44,104))
			for petal in range(6):
				_paint_disc(image,center+Vector2(random.randf_range(-11,11),random.randf_range(-11,11)),random.randf_range(13,18),Color("dd4b56"))
	return ImageTexture.create_from_image(image)

func _giant_shrine_tree() -> void:
	_rng.seed = 5
	var position := Vector3(-4.3,_world.height_at(-4.3,14.5)-0.3,14.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(20):
		for segment in range(32):
			for k in [0,2,1,1,2,3]:
				var t: float = float(level+k/2)/20
				var angle: float = float(segment+k%2)/32*TAU
				var radius: float = 1.15*(1-0.38*t)*(1+0.2*sin(angle*5+t*9)*(1-t*0.5)+0.12*sin(angle*2-t*4)+0.07*sin(angle*9+t*21)+(0.85*pow(maxf(0,cos(angle*4+0.6)),2.5)+0.22)*pow(maxf(0,1-t*3.3),2))
				var hollow_distance: float = Vector2(absf(wrapf(angle+1.065,-PI,PI))/(0.55*1.6),(t*12-2.7)/(1.05*1.6)).length()
				radius -= 0.36*(1-smoothstep(0.3,1.0,hollow_distance))*1.15*(1-0.38*t)
				st.set_uv(Vector2(float(segment+k%2)/32,t))
				st.add_vertex(Vector3(cos(angle)*radius+sin(t*4.5+0.4)*0.3+sin(t*11)*0.1,t*12,sin(angle)*radius+cos(t*3.2)*0.26+sin(t*8.5+1)*0.08))
	st.generate_normals()
	var bark := _giant_bark_material(position)
	var trunk := MeshInstance3D.new()
	trunk.name = "Ancient shrine tree"
	trunk.mesh = st.commit()
	trunk.material_override = bark
	trunk.position = position
	add_child(trunk)
	for i in range(7):
		var angle: float = float(i)/7*TAU
		_world.beam(self,position+Vector3(cos(angle)*0.5,0.7,sin(angle)*0.5),position+Vector3(cos(angle)*3,0.12,sin(angle)*3),0.32,bark)
		_world.beam(self,position+Vector3(0,10.5,0),position+Vector3(cos(angle)*4.5,13+_rng.randf()*3,sin(angle)*4.5),0.32,bark)
	var crown := MeshInstance3D.new()
	crown.mesh = _canopy(Vector3(0,14.5,0),Vector3(7,4.2,7),9,150,7,2.1,1.5,6,20)
	crown.material_override = _foliage_material(_leaf_textures[0],Color("4a7c40"),0.08)
	crown.material_override.set_shader_parameter("band_lift",0.34)
	crown.position = position
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crown)
	var ivy := SurfaceTool.new()
	ivy.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(340):
		var angle: float = -1.065+(0.85 if i%2 else -0.85)+_rng.randf_range(-0.25,0.25)
		var h: float = 0.8+pow(_rng.randf(),0.9)*7.5
		var radius: float = 1.15*(1-0.38*h/12)*1.18+0.05+_rng.randf()*0.3
		var size: float = _rng.randf_range(0.22,0.30)*1.8
		var center := Vector3(cos(angle)*radius,h,sin(angle)*radius)
		var basis := Basis(Vector3.UP,PI*0.5-angle)*Basis(Vector3.FORWARD,_rng.randf_range(-1.2,1.2))
		for k in [0,2,1,0,3,2]:
			var uv: Vector2 = [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][k]
			ivy.set_uv(uv)
			ivy.set_normal((basis*Vector3.FORWARD).normalized())
			ivy.set_color(Color(1,1,1,0.15))
			ivy.add_vertex(center+basis*Vector3((uv.x-0.5)*size,(0.5-uv.y)*size*1.15,0))
	var ivy_node := MeshInstance3D.new()
	ivy_node.name = "Climbing ivy"
	ivy_node.mesh = ivy.commit()
	ivy_node.material_override = _foliage_material(_large_leaf_texture,Color("4d8a3f"),0.04)
	ivy_node.material_override.set_shader_parameter("gradient_bottom",Vector3(0.62,0.72,0.85))
	ivy_node.material_override.set_shader_parameter("gradient_top",Vector3(1,1,0.85))
	ivy_node.position = position
	add_child(ivy_node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.6
	cylinder.height = 3
	shape.shape = cylinder
	shape.position.y = 1.5
	body.position = position
	body.add_child(shape)
	add_child(body)

func _giant_bark_material(origin: Vector3) -> ShaderMaterial:
	var random := SeededRandom.new()
	random.seed = 21
	var image := Image.create(128,512,false,Image.FORMAT_RGBA8)
	image.fill(Color8(118,118,108))
	for i in range(140):
		var change: int = random.randi_range(-30,19)
		var color := Color((118+change)/255.0,(118+change)/255.0,(108+change)/255.0,random.randf_range(0.35,0.75))
		var rect := Rect2i(random.randi_range(0,127),random.randi_range(0,511),random.randi_range(2,7),random.randi_range(30,150))
		for y in range(rect.position.y,mini(512,rect.end.y)):
			for x in range(rect.position.x,mini(128,rect.end.x)):
				image.set_pixel(x,y,image.get_pixel(x,y).blend(color))
	for i in range(60):
		var p := Vector2(random.randf()*128,random.randf()*512)
		_paint_stroke(image,p,p+Vector2(0,random.randf_range(20,100)),random.randf_range(1,3),Color(20/255.0,14/255.0,10/255.0,random.randf_range(0.25,0.6)))
	for i in range(70):
		_paint_ellipse(image,Vector2(random.randf()*128,random.randf()*512),Vector2(random.randf_range(4,14),random.randf_range(8,34)),Color(94/255.0,126/255.0,92/255.0,random.randf_range(0.25,0.6)))
	for i in range(30):
		_paint_ellipse(image,Vector2(random.randf()*128,random.randf()*512),Vector2(random.randf_range(3,9),random.randf_range(6,24)),Color(158/255.0,156/255.0,142/255.0,random.randf_range(0.2,0.5)))
	for pass_index in range(2):
		for i in range(70 if pass_index==0 else 60):
			var start := Vector2(random.randf()*128,random.randf()*512-40)
			var length: float = random.randf_range(40,180)
			var drift: float = random.randf_range(-7,7)
			var color := Color(152/255.0,152/255.0,136/255.0,random.randf_range(0.55,0.9)) if pass_index==0 else Color(72/255.0,70/255.0,62/255.0,random.randf_range(0.6,0.95))
			var width: float = random.randf_range(2,4)
			var previous := start
			for step in range(1,13):
				var t: float = float(step)/12
				var p := start+Vector2(sin(t*PI)*drift,length*t)
				_paint_stroke(image,previous,p,width,color)
				previous = p
	for i in range(4):
		var x: float = (i+0.3+random.randf()*0.5)/4*128
		var previous := Vector2(x,-10)
		for step in range(1,25):
			var p := Vector2(x+sin(step*0.21+i)*8,step/24.0*532-10)
			_paint_stroke(image,previous,p,4,Color(72/255.0,70/255.0,62/255.0,0.9))
			_paint_stroke(image,previous+Vector2(4,0),p+Vector2(4,0),2,Color(152/255.0,152/255.0,136/255.0,0.5))
			previous = p
	image.generate_mipmaps()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode specular_disabled;
uniform sampler2D bark_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 bark_color : source_color = vec4(0.706,0.737,0.722,1.0);
uniform vec3 tree_origin;
varying vec3 world_position;
float hash_b(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise_b(vec2 p) { vec2 a=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash_b(a),hash_b(a+vec2(1,0)),f.x),mix(hash_b(a+vec2(0,1)),hash_b(a+vec2(1,1)),f.x),f.y); }
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec3 delta=world_position-tree_origin;
 float angle=atan(delta.z,delta.x);
 float angular_distance=abs(mod(angle+1.065+PI,TAU)-PI);
 float hollow=length(vec2(angular_distance/(0.34*1.6),(delta.y-2.7)/(0.85*1.6)));
 hollow+=(noise_b(vec2(angle*6.0,world_position.y*2.2))-0.5)*0.5;
 float cavity=1.0-smoothstep(0.55,1.0,hollow);
 float lip=(1.0-smoothstep(1.0,1.35,hollow))*(1.0-cavity);
 ALBEDO=texture(bark_texture,UV*vec2(2.0,1.6)).rgb*bark_color.rgb;
 ALBEDO=mix(ALBEDO,vec3(0.12,0.10,0.08),lip*0.6);
 ALBEDO=mix(ALBEDO,vec3(0.0015,0.002,0.003),cavity);
 ROUGHNESS=1.0;
}
void light() { float raw=dot(NORMAL,LIGHT); float band=(smoothstep(-0.4,0.15,raw)*0.5+smoothstep(0.2,0.7,raw)*0.4)*0.9+0.14; DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI; }
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("bark_texture",ImageTexture.create_from_image(image))
	material.set_shader_parameter("tree_origin",origin)
	return material

func _area_flora() -> void:
	# Shrine's authored flora is separate from the background distribution.
	_giant_shrine_tree()
	_broad_tree(10.5,24.5,9.5,4.4,61,{"color":4025912,"leaf_lift":0.12})
	_broad_tree(-14.5,25.5,4,4.5,67)
	for row in [[13.5,30,12,62],[8,39,11,63],[-12,38,9,64],[-12.5,26,9,66],[-4.5,37.5,7,65],[-5.2,28.5,6.5,68]]:
		_pine_tree(row[0],row[1],row[2],row[3])
	_shrine_flowers(Vector2(-0.5,15),8.5,288,Color("a696ca"),300)
	_shrine_flowers(Vector2(-0.5,15),8.5,192,Color("eeae36"),301)
	_shrine_flowers(Vector2(5,12),4,24,Color("dd4b56"),302,0.8)
	_shrine_flowers(Vector2(5,12),4,56,Color("eeae36"),303,0.8)
	_meadow(Rect2(-12,6,24,13.5),7.5,1,true)
	_rosettes([[-7.5,15,2,3],[-3,14.8,1.6,5],[-9.5,16,1.6,7],[-1,13.5,1.4,9],[6.5,14.5,1.7,11],[3.5,13.5,1.2,13],[-11,9,1.4,15]])
	# Village trees form the massive green roof over the lane and hide the railway.
	for row in [[-5,89,10,6.5,41],[-43,90,9,5.5,42],[14,88,9,5.5,43],[-7,62.8,12,10,44],[-20,63.8,13,12,47],[-5.6,81.3,13,9.5,46],[-31,73.6,4.5,8,48],[-38.5,71,4.5,8,50],[-34.5,68.8,4.5,7,51],[-30,61.5,8,9,49]]:
		_broad_tree(row[0],row[1],row[2],row[3],row[4],{"clusters":220 if row[2]==4.5 else 110})
	# Paddy approach uses unusually small leaf cards (0.4m rather than 1.6m).
	_broad_tree(58.8,-3.6,4.4,2.9,12,{"card_size":0.4,"clusters":650,"cluster_radius":0.6,"leaf_lift":0.34,"color":5672000})
	_broad_tree(61.6,-3,1.2,1.9,14,{"card_size":0.42,"clusters":360,"cluster_radius":0.55,"leaf_lift":0.3})
	_broad_tree(49,35,8,5,12)
	for row in [[47,-3,10,13],[101.5,12,9.5,19],[104,16,7.5,20]]:
		_pine_tree(row[0],row[1],row[2],row[3])
	for row in [[76,61,5.5,4.5,40],[81,62,6,4.5,41],[86,61.5,6.5,5,42],[91,63,6,4.5,43],[96,62,6.5,5,44],[101,62.5,6,4.5,45],[106,64,6,4.5,46],[111,65,5.5,4.5,47]]:
		_broad_tree(row[0],row[1],row[2],row[3],row[4],{"color":4091450})
	_farm_flora()
	_rail_flora()
	_vending_flora()

func _farm_flora() -> void:
	_broad_tree(57.6,66.8,0.4,1.8,41,{"color":4160066,"leaf_lift":0.4,"card_size":0.9,"clusters":100,"cluster_radius":0.8,"shadow":false})
	_broad_tree(59.5,67.2,9,4.5,42,{"color":3499578,"leaf_lift":0.3,"card_size":1.3,"shadow":false})
	_broad_tree(47.4,63.2,6,4.6,43,{"color":3499578,"leaf_lift":0.3,"card_size":1.3,"shadow":false})
	for row in [[58,77.5,1.5,2.5,71],[54,78,1.5,2.5,72],[40,83,7,5,65],[46,83,4.5,4.5,61],[54,83.5,4.5,4.5,62],[58,84,4.5,4.5,66],[62,83,4.5,4.5,63],[70,82,7,5,64],[43,86,6.5,4.5,21],[52,86.5,5,4.5,22],[60,85,5,4.5,24],[34,86,7,4.5,23],[36,84,10,6,81],[41,86.5,11,6,82],[30,82,9,5.5,83],[24,78,6.5,4.5,25],[69,84,6.5,5.5,28],[67.5,82.5,4.5,5,31],[72.5,85.5,6,5,32],[75.5,87,7,5.5,29],[81,89,7,5.5,30]]:
		_broad_tree(row[0],row[1],row[2],row[3],row[4],{"color":8368718 if row[2]==1.5 else 3038260})
	for row in [[44,81,51],[50,81.5,52],[56,81,53],[62,81.5,54],[68,81,55],[38,82,56],[74,83,57]]:
		_broad_tree(row[0],row[1],0.3,1.6,row[2],{"color":2907187})

func _rail_flora() -> void:
	var rows: Array = []
	var placements := [[3.6,0.6,72],[4.2,-0.8,71],[4.8,1.8,70],[5.5,0.2,70],[6.2,-1.6,70],[6.8,1.2,69],[7.5,-0.4,69],[8.2,2.4,69],[7.4,-2.6,68],[7.2,3,68],[1.6,0.5,76],[1.9,-0.9,78],[2.2,1.4,76],[2.5,-1.8,77],[2.8,0.2,74],[2,2.2,74],[2.4,-2.6,76],[1.7,-1.6,80],[3,-3,74],[3.1,2.8,74],[3.4,2.2,74],[4,3.2,72],[5,4.2,70],[6.4,5.4,68],[7.4,4.6,67],[7,6.2,66],[4,4.9,46],[5,5.9,34],[6,7,22],[3.5,4.4,58],[4,-4.9,42],[5,-5.9,30],[6,-6.9,46],[7.2,-8,36],[4.6,-5.6,56],[3.6,-4.4,62],[6,-2.8,70],[7,-4.2,69],[7.4,-3.4,68],[6.6,-2,69],[5,-4.2,66],[5.6,-5.2,62],[6.2,-4.6,64],[6.8,-5.8,60],[7.2,-5,63],[6.5,-6.6,58],[7.4,-6.2,61],[5.8,-6,56]]
	for i in range(placements.size()):
		var row: Array = placements[i]
		var p := Vector2(19.2+0.1213*row[0]+0.9926*row[1],80+0.9926*row[0]-0.1213*row[1])
		var leaf_top: float = 4.38+tan(0.41+atan(((50-row[2])/50.0)*0.6009))*row[0]
		var size: float = clampf(0.4+row[0]*0.12,0.6,1.1)
		var lift: float = clampf(leaf_top-_world.height_at(p.x,p.y)-0.95*size,0,2.6)
		rows.append([p.x,p.y,size,11+i*7,lift,3 if lift>1.2 else (2 if lift>0.5 else 1)])
	_rosettes(rows,Color.hex((2049076<<8)|255))
	for row in [[6,7.5,6.5,3.2,51],[6.5,-8,5.5,2.6,52]]:
		_broad_tree(19.2+0.1213*row[0]+0.9926*row[1],80+0.9926*row[0]-0.1213*row[1],row[2],row[3],row[4],{"color":2904640})
	for row in [[30,93.5,4.4,3,43],[36.5,94.5,4.8,3.2,44],[42.5,93.5,4.6,3,45],[3,93,4.4,3,46],[-2,92,8,5,31],[56,94,8.5,5,32],[-56,70,7,4.5,33],[-39,69,7.5,4.5,34]]:
		_broad_tree(row[0],row[1],row[2],row[3],row[4],{"color":2773056})
	_rosettes([[33.5,91.5,1.8,1],[40,91.5,1.8,2],[10,92.5,1.8,3],[34,80,1.2,4],[38,81.5,1,5]],Color.hex((2049076<<8)|255))
	_meadow(Rect2(6,74,28,14),6,0.6,false,{"base":Vector3(0.07,0.18,0.15),"mid":Vector3(0.14,0.3,0.19),"tip":Vector3(0.27,0.42,0.23),"seed_heads":0.05})

func _vending_position(forward: float,side: float) -> Vector2:
	return Vector2(-64.3-sin(-1.95)*forward+cos(-1.95)*side,58.6-cos(-1.95)*forward-sin(-1.95)*side)

func _vending_flora() -> void:
	# Trees and undergrowth framing the active machines and the abandoned machine.
	for row in [[-92,2,9,6,51,4880954],[-88,44,9,6,52,4091450],[-69.2,34.6,3.5,3.5,55,4091450],[-75,37,6,4.2,56,4880954],[-77,36,6,4.2,59,4091450],[-77.5,39,6,4,57,4091450],[-73.5,38,1.2,3,58,4091450],[-77,33,0.8,3.2,64,4880954],[-70.8,37.5,0.3,2,61,4091450],[-71.5,36,0.3,2,62,4880954],[-50,32,11,3,53,4091450]]:
		_broad_tree(row[0],row[1],row[2],row[3],row[4],{"color":row[5],"clusters":150 if row[4] in [55,56,59,57] else 110,"bark":2902574})
	_broad_tree(-64,30.4,3.3,3.9,53,{"color":3037748,"bark":3814440,"card_size":1,"clusters":220,"cluster_radius":0.95})
	_broad_tree(-64.2,22.4,3.6,3.4,54,{"color":3367482,"bark":3814440,"card_size":1,"clusters":220,"cluster_radius":0.95})
	_broad_tree(-75,32.5,5,3,65,{"color":4091450,"bark":2902574,"clusters":180,"cluster_radius":1.1})
	for row in [[-124,6,4,3.5,4091450],[-125,11,4.5,3.8,4880954],[-124,16,4,3.5,4091450],[-126,21,4.5,3.8,4091450],[-124,26,4.2,3.5,4880954],[-126,31,4.5,3.8,4091450],[-124,36,4,3.5,4880954],[-125,41,4.5,3.8,4091450],[-124,46,4,3.5,4091450]]:
		_broad_tree(row[0],row[1],row[2],row[3],70+int((row[1]-6)/5),{"color":row[4]})
	_rosettes([[-69.4,27.6,1.4,39],[-69,26,1.2,41],[-69.8,29.2,1.35,43],[-69.2,31,1.2,45],[-62.2,13.5,1.3,47],[-62.4,37.2,1.3,49]],Color.hex((3963450<<8)|255))
	_meadow(Rect2(-84,6,16.5,38),3,0.95,false,{"base":Vector3(0.3,0.44,0.19),"mid":Vector3(0.52,0.65,0.27),"tip":Vector3(0.74,0.79,0.38)})
	_meadow(Rect2(-67.55,11,0.7,28),16,0.65,false,{"force":true,"base":Vector3(0.16,0.28,0.12),"mid":Vector3(0.28,0.5,0.24),"tip":Vector3(0.42,0.64,0.32)})
	var groups := [
		{"color":3366970,"tip":5933642,"rows":[[1.6,-1,1.3],[1.2,-2,1.2],[2.2,-2.6,1.5],[1.4,-0.2,1],[1.2,0.6,0.9],[3.2,-3.4,1.6],[1.8,-0.5,1.2],[2,-1.6,1.4],[2.6,-3.6,1.5]]},
		{"color":3829824,"tip":7645270,"rows":[[0.9,-1.7,1.9],[1.2,-2.4,1.8],[1.15,-0.9,0.9],[1.05,-0.2,0.8],[1.2,0.5,0.75],[1.3,1.3,0.8],[0.95,-1.2,0.9]]},
		{"color":3894077,"tip":0,"rows":[[5,1.5,1.6],[6.5,3.5,1.7],[5.8,2.6,1.4],[7.2,5,1.6]]},
		{"color":3499580,"tip":6987346,"rows":[[1.5,-1.9,1.7],[2.1,-2.5,1.9],[1.25,-1.6,1.4],[4.8,-0.6,1.8],[5.3,-1.5,1.7],[4.4,-1,1.9],[4.6,0.1,1.7],[5.6,-0.9,2],[4.2,-0.2,1.6]]}
	]
	for group in groups:
		var rows: Array = []
		for row in group.rows:
			var p := _vending_position(row[0],row[1])
			rows.append([p.x,p.y,row[2],100+int(row[0]*7)+int(row[1]*5)])
		_rosettes(rows,Color.hex((int(group.color)<<8)|255),Color.hex((int(group.tip)<<8)|255) if group.tip>0 else Color.TRANSPARENT)
	for row in [[6.2,-3.6,1.2,1.8,63,2773056,150,0.9,0.9],[5.4,2.4,0,2,64,3103285,140,0.9,0.9],[7,4.6,0,2.2,66,3564090,140,0.9,0.9],[11,8.5,5.5,3.6,68,3564090,110,1.6,1.2],[6,9.5,4.5,3.2,69,3103285,110,1.6,1.2],[-2.4,-2.4,4.5,3.4,81,3103285,14,1.6,1.4],[0.8,-2.6,5.2,1.9,83,3498810,70,1.4,1]]:
		var p := _vending_position(row[0],row[1])
		_broad_tree(p.x,p.y,row[2],row[3],row[4],{"color":row[5],"clusters":row[6],"card_size":row[7],"cluster_radius":row[8]})

func _clear_cache_owners(node: Node) -> void:
	node.owner=null
	for child in node.get_children(): _clear_cache_owners(child)
