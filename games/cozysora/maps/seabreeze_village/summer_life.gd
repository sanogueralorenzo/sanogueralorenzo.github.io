extends Node3D
## Small cream butterflies over the opening verge, and drifting summer pollen.
var creatures: Array[Dictionary] = []
var world: Node3D
var clock := 3.0


func build(level: Node3D) -> void:
	world = level
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color("fff3c0")
	cream.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cream.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 70:
		var patch: Vector2 = [
			Vector2(-3.3, -4.6), Vector2(-3, -6.2), Vector2(-3.4, -3.4), Vector2(-1.5, -5.5), Vector2(-10, 0)
		][rng.randi_range(0, 4)]
		var pos := patch + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var body := Node3D.new()
		add_child(body)
		var wings: Array[Node3D] = []
		for side in [-1, 1]:
			var wing := Node3D.new()
			body.add_child(wing)
			var mesh := PrismMesh.new()
			mesh.size = Vector3(.075, .006, .058)
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.material_override = cream
			visual.position.x = side * .038
			wing.add_child(visual)
			wings.append(wing)
		creatures.append(
			{"body": body, "wings": wings, "home": pos, "phase": rng.randf() * 100, "speed": rng.randf_range(.6, 1.2)}
		)
	preload("res://maps/seabreeze_village/air.tres").install(self, Vector3(-6, 4, -1))


func _process(delta: float) -> void:
	clock += delta
	for creature in creatures:
		var t: float = clock * creature.speed + creature.phase
		var home: Vector2 = creature.home
		var x: float = home.x + sin(t * .7) * .6
		var z: float = home.y + cos(t * .5) * .6
		creature.body.position = Vector3(x, world.height_at(x, z) + .6 + sin(t) * .3, z)
		creature.body.rotation = Vector3(.4, t * .5, sin(t * 2) * .3)
		creature.wings[0].rotation.z = sin(clock * 22 + creature.phase) * .9
		creature.wings[1].rotation.z = -sin(clock * 22 + creature.phase) * .9
