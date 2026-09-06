class_name LastCastActor
extends CharacterBody3D
## Independent procedural sailor, launch, and third-person controller.

var sailing := false
var locked := false
var toggle_controls := false
var move_latch := Vector2.ZERO
var camera: Camera3D
var boat: Node3D
var rod_tip: Node3D
var camera_yaw := 0.28
var camera_pitch := 0.30
var camera_distance := 12.0
var boat_speed := 0.0
var boat_heading := 0.0
var model: Node3D
var torso: Node3D
var rod: Node3D
var limbs: Array[Node3D] = []
var knees: Array[Node3D] = []
var line_mesh: ImmediateMesh
var line_node: MeshInstance3D
var wake_mesh: ImmediateMesh
var wake_node: MeshInstance3D
var fishing := false
var line_active := false
var line_target := Vector3.ZERO
var fish_fighting := false
var fish_surge := false
var line_tension := 0.0
var bobber: Node3D
var hooked_fish: Node3D
var fish_tail: Node3D
var rod_segments: Array[MeshInstance3D] = []
var splash_pool: Array[Dictionary] = []
var water_rings: Array[Dictionary] = []
var landing_time := -1.0
var landing_start := Vector3.ZERO
var splash_timer := 0.0
var cast_animation := -1.0
var cast_start := Vector3.ZERO
var bobber_dip := 0.0
var waiting_cast := false
var elapsed := 0.0
var gait := 0.0
var look_target := Vector3.ZERO
var collision: CollisionShape3D
var materials: Dictionary = {}
var wake_points: Array[Vector3] = []
var wake_clock := 0.0
var camera_ready := false
var view_yaw := 0.28
var fishing_orbit := 1.05
var cast_bearing := 0.0
var boat_camera_orbit := 0.0

func setup() -> void:
	name = "Sailor"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	safe_margin = 0.025
	var bindings := {"lc_left": KEY_A, "lc_right": KEY_D, "lc_up": KEY_W, "lc_down": KEY_S, "lc_sprint": KEY_SHIFT}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)
	collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.84
	add_child(collision)
	_build_sailor()
	_build_boat()
	camera = Camera3D.new()
	camera.name = "ThirdPersonCamera"
	camera.fov = 59
	camera.near = 0.12
	camera.far = 500
	get_parent().add_child(camera)
	camera.current = true
	line_mesh = ImmediateMesh.new()
	line_node = MeshInstance3D.new()
	line_node.mesh = line_mesh
	line_node.material_override = _material("line", Color("fff8d4"), true)
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(line_node)
	wake_mesh = ImmediateMesh.new()
	wake_node = MeshInstance3D.new()
	wake_node.mesh = wake_mesh
	wake_node.material_override = _material("foam", Color("c6f1e6"), true)
	wake_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(wake_node)
	_build_fishing_visuals()
	reset_home()

func board() -> void:
	boat_camera_orbit = 0.0
	clear_controls()
	sailing = true
	velocity = Vector3.ZERO
	boat_speed = 0.0
	boat_heading = 0.0
	collision_mask = 0
	position = Vector3(3, 0.35, 7)
	boat.visible = true
	boat.position = position
	boat.rotation.y = boat_heading
	model.rotation.y = boat_heading
	camera_distance = 12.5
	wake_points.clear()

func dock() -> void:
	camera_yaw = view_yaw
	clear_controls()
	sailing = false
	velocity = Vector3.ZERO
	boat_speed = 0.0
	collision_mask = 1
	position = Vector3(0, 1.03, 6)
	boat.position = Vector3(3, 0.35, 7)
	boat.rotation = Vector3.ZERO
	camera_distance = 12.0
	wake_points.clear()
	set_fishing(false)

func reset_home() -> void:
	clear_controls()
	sailing = false
	locked = false
	fishing = false
	boat_speed = 0.0
	velocity = Vector3.ZERO
	collision_mask = 1
	position = Vector3(-12, 1.03, 2)
	model.rotation.y = 0
	boat.position = Vector3(3, 0.35, 7)
	boat.rotation = Vector3.ZERO
	wake_points.clear()
	if line_node != null:
		line_active = false
		line_node.visible = false

func clear_controls() -> void:
	move_latch = Vector2.ZERO
	velocity = Vector3.ZERO
	boat_speed = 0.0

func set_fishing(active: bool) -> void:
	fishing = active
	locked = active
	if active:
		fishing_orbit = 1.05
		clear_controls()
	if not active:
		line_active = false
		if line_node != null: line_node.visible = false

func set_line_target(target: Vector3, active: bool) -> void:
	if active and not line_active:
		var aim := target-global_position
		cast_bearing=atan2(aim.x,aim.z)
	line_target = target
	line_active = active
	line_node.visible = active
	if active:
		var aim := target - global_position
		if Vector2(aim.x, aim.z).length() > 0.1:
			model.rotation.y = atan2(aim.x, aim.z)

func _unhandled_input(event: InputEvent) -> void:
	if toggle_controls and not locked and event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match code:
			KEY_W: move_latch.y = 0.0 if move_latch.y < 0 else -1.0
			KEY_S: move_latch.y = 0.0 if move_latch.y > 0 else 1.0
			KEY_A: move_latch.x = 0.0 if move_latch.x < 0 else -1.0
			KEY_D: move_latch.x = 0.0 if move_latch.x > 0 else 1.0
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if fishing: fishing_orbit -= event.relative.x * 0.005
		elif sailing: boat_camera_orbit -= event.relative.x * 0.005
		else: camera_yaw -= event.relative.x * 0.005
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.003, 0.2, 0.98)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(5.5, camera_distance - 0.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(17.0, camera_distance + 0.7)

func _physics_process(dt: float) -> void:
	if camera == null: return
	elapsed += dt
	if locked: clear_controls()
	elif not toggle_controls: move_latch = Vector2.ZERO
	if not locked:
		var orbit_input := float(Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_RIGHT))
		if sailing: boat_camera_orbit += orbit_input * dt * 1.5
		else: camera_yaw += orbit_input * dt * 1.5
		if Input.is_physical_key_pressed(KEY_UP): camera_pitch = maxf(0.2, camera_pitch - dt * 0.6)
		if Input.is_physical_key_pressed(KEY_DOWN): camera_pitch = minf(0.98, camera_pitch + dt * 0.6)
	if sailing:
		_sail(dt)
	else:
		_walk(dt)
	_animate(dt)
	_place_camera(dt)
	_draw_line()
	_draw_wake(dt)
	_animate_fishing_visuals(dt)

func _walk(dt: float) -> void:
	var axis := Vector2.ZERO if locked else (move_latch.normalized() if toggle_controls else Input.get_vector("lc_left", "lc_right", "lc_up", "lc_down"))
	# Follow the actual rendered view, including the return from a fishing orbit.
	var forward := -camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	var direction := right * axis.x - forward * axis.y
	var speed := 5.6 if Input.is_action_pressed("lc_sprint") else 3.7
	velocity.x = move_toward(velocity.x, direction.x * speed, dt * 24)
	velocity.z = move_toward(velocity.z, direction.z * speed, dt * 24)
	velocity.y = -2.0 if is_on_floor() else maxf(-18, velocity.y - dt * 25)
	if direction.length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), 1 - exp(-dt * 14))
	var old := position
	move_and_slide()
	# Explicit shoreline safety makes edges dependable without invisible death planes.
	if not _walkable(position):
		var along_x := Vector3(position.x, position.y, old.z)
		var along_z := Vector3(old.x, position.y, position.z)
		if _walkable(along_x): position = along_x
		elif _walkable(along_z): position = along_z
		else: position.x = old.x; position.z = old.z
	if position.y < 1.0:
		position.y = 1.0
		velocity.y = 0

func _walkable(p: Vector3) -> bool:
	if p.x > -21.7 and p.x < 21.7 and p.z > -4.1 and p.z < -0.1: return true
	if p.x > -1.22 and p.x < 1.22 and p.z > -1.0 and p.z < 7.65: return true
	if p.x > -13.22 and p.x < -10.78 and p.z > -1.0 and p.z < 4.68: return true
	return false

func _sail(dt: float) -> void:
	var throttle := 0.0 if locked else (-move_latch.y if toggle_controls else Input.get_axis("lc_down", "lc_up"))
	var turn := 0.0 if locked else (move_latch.x if toggle_controls else Input.get_axis("lc_left", "lc_right"))
	var wanted := throttle * (8.2 if throttle > 0 else 3.8)
	boat_speed = move_toward(boat_speed, wanted, dt * (7.5 if throttle == 0 else 5.5))
	boat_heading -= turn * dt * (1.25 + minf(absf(boat_speed), 5.0) * 0.06) * (-1.0 if boat_speed < -0.1 else 1.0)
	# Positive-Z is the bow; right input turns toward the sailor's right.
	var direction := Vector3(sin(boat_heading), 0, cos(boat_heading))
	var next := position + direction * boat_speed * dt
	next.x = clampf(next.x, -31, 31)
	next.z = clampf(next.z, 4.0, 44)
	if absf(next.x) < 2.5 and next.z < 9.7:
		if position.z >= 9.7: next.z = 9.7
		else: next.x = 2.5 if position.x >= 0 else -2.5
	if next.x > -14.5 and next.x < -9.5 and next.z < 6.8:
		if position.z >= 6.8: next.z = 6.8
		else: next.x = -9.5 if position.x >= -12 else -14.5
	position = next
	position.y = 0.35 + sin(elapsed * 1.8) * 0.045 + sin(elapsed * 3.3) * 0.015
	boat.position = position
	boat.rotation = Vector3(sin(elapsed * 1.8) * 0.016, boat_heading, sin(elapsed * 1.45) * 0.025 + turn * boat_speed * 0.006)
	if not fishing: model.rotation.y = lerp_angle(model.rotation.y, boat_heading, minf(1, dt * 9))

func _animate(dt: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if not sailing else 0.0
	gait += dt * speed * 2.7
	var seated := sailing and not fishing
	model.position.y = (-0.4 if seated else 0.16) if sailing else absf(sin(gait)) * 0.035 * minf(speed, 1)
	model.position.x = -sin(boat_heading) * 0.82 if seated else 0.0
	model.position.z = -cos(boat_heading) * 0.82 if seated else 0.0
	for knee: Node3D in knees:
		knee.rotation.x = lerpf(knee.rotation.x, 1.1 if seated else 0.0, minf(1, dt * 9))
	torso.rotation.x = lerpf(torso.rotation.x, -0.12 if fishing else (0.04 if sailing else -speed * 0.012), minf(1, dt * 7))
	for index in limbs.size():
		var limb := limbs[index]
		var phase := gait + (PI if index % 2 else 0.0)
		var angle := sin(phase) * minf(speed / 4, 1) * 0.6
		if index < 2:
			if sailing: angle = -1.1 if seated else 0.0
		else:
			angle *= -0.7
			if fishing: angle = -0.95 if index == 2 else -1.15
			elif sailing: angle = -0.45
		limb.rotation.x = lerpf(limb.rotation.x, angle, minf(1, dt * 12))
	var rod_pose := (-0.40 if waiting_cast else 0.24 + line_tension * 0.15) if fishing else 0.05
	rod.rotation.x = lerpf(rod.rotation.x, rod_pose, minf(1, dt * 7))
	_bend_rod()
	rod.rotation.z = sin(elapsed * 2.1) * (0.012 if fishing else 0.025)
	if not sailing:
		boat.position.y = 0.35 + sin(elapsed * 1.8) * 0.04
		boat.rotation.z = sin(elapsed * 1.45) * 0.022

func _place_camera(dt: float) -> void:
	var wanted_target := global_position + Vector3(0, 1.35 if not sailing else 1.0, 0)
	var desired_yaw := boat_heading + PI + boat_camera_orbit if sailing else camera_yaw
	if sailing and not fishing: wanted_target += Vector3(sin(boat_heading),0,cos(boat_heading))*2.5
	if fishing and line_active:
		desired_yaw = cast_bearing + fishing_orbit
		wanted_target = wanted_target.lerp(line_target + Vector3.UP * 1.0, 0.40)
		# Reserve the right third for fight cues without covering the boat or sailor.
		var camera_right := Vector3(cos(desired_yaw), 0, -sin(desired_yaw))
		wanted_target += camera_right * 2.5
	view_yaw = lerp_angle(view_yaw, desired_yaw, 1.0 - exp(-dt * 3.5)) if camera_ready else desired_yaw
	if not camera_ready:
		look_target = wanted_target
	else:
		look_target = look_target.lerp(wanted_target, 1 - exp(-dt * 10))
	var offset := Vector3(sin(view_yaw) * cos(camera_pitch), sin(camera_pitch), cos(view_yaw) * cos(camera_pitch)) * camera_distance
	var desired := look_target + offset
	var query := PhysicsRayQueryParameters3D.create(look_target, desired, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): desired = hit.position + hit.normal * 0.35
	var camera_at := camera.global_position.lerp(desired, 1 - exp(-dt * 12)) if camera_ready else desired
	# The smoothed orbit can cross a wall even when its final destination is clear.
	var smooth_query := PhysicsRayQueryParameters3D.create(look_target, camera_at, 1, [get_rid()])
	var smooth_hit := get_world_3d().direct_space_state.intersect_ray(smooth_query)
	if not smooth_hit.is_empty(): camera_at = smooth_hit.position + smooth_hit.normal * 0.35
	camera.global_position = camera_at
	if camera.global_position.distance_to(look_target) > 0.05:
		camera.look_at(look_target, Vector3.UP)
	camera_ready = true
	# Hide the avatar for a tightly occluded camera instead of filling the view.
	model.visible = camera.global_position.distance_to(model.global_position + Vector3.UP*1.3) > .85

func _draw_line() -> void:
	line_mesh.clear_surfaces()
	if not line_active or waiting_cast: return
	var start := rod_tip.global_position
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 33:
		var t := float(i) / 32
		var endpoint := bobber.global_position + Vector3.UP * 0.23 if bobber.visible else line_target
		var point := start.lerp(endpoint, t)
		point.y -= sin(t * PI) * minf(0.55, start.distance_to(endpoint) * 0.025) * (1.0 - line_tension * 0.92)
		line_mesh.surface_add_vertex(point)
	line_mesh.surface_end()

func _draw_wake(dt: float) -> void:
	wake_clock += dt
	if sailing and absf(boat_speed) > 0.6 and wake_clock > 0.13:
		wake_clock = 0
		var stern := position - Vector3(sin(boat_heading), 0, cos(boat_heading)) * 1.55
		stern.y = 0.1
		wake_points.push_front(stern)
		if wake_points.size() > 25: wake_points.pop_back()
	elif wake_clock > 0.16 and not wake_points.is_empty():
		wake_clock = 0
		wake_points.pop_back()
	wake_mesh.clear_surfaces()
	if wake_points.size() < 2: return
	wake_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, wake_points.size()):
		var tangent := (wake_points[i - 1] - wake_points[i]).normalized()
		var side := Vector3(tangent.z, 0, -tangent.x)
		var width := 0.65 + i * 0.095
		for sign_value in [-1, 1]:
			wake_mesh.surface_add_vertex(wake_points[i] + side * width * sign_value + Vector3.UP * sin(elapsed * 4 + i) * 0.009)
			wake_mesh.surface_add_vertex(wake_points[i - 1] + side * (width - 0.06) * sign_value)
	wake_mesh.surface_end()

func set_fish_appearance(data: Dictionary) -> void:
	if hooked_fish == null: return
	var signature := bool(data.get("signature", false))
	var region := clampi(int(data.get("region", 0)), 0, 2)
	hooked_fish.scale = Vector3.ONE * (1.10 if signature else 0.62)
	var backs: Array[Color] = [Color("397f83"), Color("568d78"), Color("426993")]
	var signatures: Array[Color] = [Color("b98d32"), Color("d88779"), Color("427fbd")]
	(materials["fish_back"] as StandardMaterial3D).albedo_color = signatures[region] if signature else backs[region]
	(materials["fish_silver"] as StandardMaterial3D).albedo_color = Color("e3d5a4") if signature and region == 0 else (Color("ead9d6") if signature and region == 1 else Color("acccc4"))
	(materials["fish_fin"] as StandardMaterial3D).albedo_color = Color("d8aa59") if region == 0 else (Color("eab2a1") if region == 1 else Color("8aaed1"))

func fishing_cue(kind: String) -> void:
	if bobber == null: return
	var at := line_target
	at.y = 0.12
	match kind:
		"cast":
			waiting_cast = true
			landing_time = -1
			fish_fighting = false
		"splash":
			waiting_cast = false
			cast_animation = 0
			cast_start = rod_tip.global_position
		"strike":
			bobber_dip = 0.65
			_splash(at, 11, 0.85)
		"hook":
			hooked_fish.global_position = at
			hooked_fish.rotation.y = model.rotation.y + PI
			fish_fighting = true
			_splash(at, 14, 1.05)
		"surge":
			_splash(at, 20, 1.35)
		"land":
			if not fish_fighting and not line_active and landing_time < 0: return
			# Fly the catch along the same visible line, ending at the sailor's hands.
			landing_time = 0
			landing_start = hooked_fish.global_position if hooked_fish.visible else at
			_splash(at, 18, 1.15)
		"escape":
			_splash(at, 8, 0.65)
			fish_fighting = false

func _build_fishing_visuals() -> void:
	bobber = _group(get_parent(), Vector3.ZERO)
	bobber.name = "VisibleBobber"
	var cream := _material("float_cream", Color("fff1d6"))
	var coral := _material("float_coral", Color("db5149"))
	var dark := _material("float_dark", Color("304755"))
	_sphere(bobber, Vector3(0, 0.085, 0), Vector3(0.10, 0.15, 0.10), cream)
	_sphere(bobber, Vector3(0, 0.18, 0), Vector3(0.099, 0.083, 0.099), coral)
	_segment(bobber, Vector3(0, 0.19, 0), Vector3(0, 0.40, 0), 0.016, dark)
	_sphere(bobber, Vector3(0, 0.40, 0), Vector3(0.04, 0.04, 0.04), coral)
	bobber.visible = false
	hooked_fish = _group(get_parent(), Vector3.ZERO)
	hooked_fish.name = "HookedFish"
	var silver := _material("fish_silver", Color("acccc4"))
	var dorsal := _material("fish_back", Color("397f83"))
	var fin := _material("fish_fin", Color("d4ad69"))
	var eye := _material("fish_eye", Color("162f3b"))
	_sphere(hooked_fish, Vector3.ZERO, Vector3(0.20, 0.23, 0.58), silver)
	_sphere(hooked_fish, Vector3(0, 0.12, -0.02), Vector3(0.176, 0.13, 0.51), dorsal)
	_sphere(hooked_fish, Vector3(0, -0.11, 0.07), Vector3(0.15, 0.12, 0.42), cream)
	for side in [-1, 1]:
		_sphere(hooked_fish, Vector3(side * 0.145, 0.05, 0.38), Vector3(0.048, 0.05, 0.038), cream)
		_sphere(hooked_fish, Vector3(side * 0.184, 0.05, 0.385), Vector3(0.020, 0.028, 0.023), eye)
		_fin(hooked_fish, Vector3(side * 0.12, -0.02, 0.10), Vector3(side * 0.44, -0.09, -0.16), Vector3(side * 0.14, -0.07, -0.25), fin)
		_segment(hooked_fish, Vector3(side * 0.176, -0.05, 0.27), Vector3(side * 0.16, 0.12, 0.23), 0.012, dorsal)
	_fin(hooked_fish, Vector3(0, 0.17, 0.11), Vector3(0, 0.48, -0.28), Vector3(0, 0.18, -0.40), fin)
	fish_tail = _group(hooked_fish, Vector3(0, 0, -0.51))
	_fin(fish_tail, Vector3(0, 0, 0), Vector3(0, 0.34, -0.40), Vector3(0, 0.0, -0.29), fin)
	_fin(fish_tail, Vector3(0, 0, 0), Vector3(0, -0.34, -0.40), Vector3(0, 0.0, -0.29), fin)
	hooked_fish.visible = false
	# Reuse a fixed pool: expressive bursts without per-frame object allocation.
	var foam := _material("droplet", Color("dcfaf0"), true)
	for i in 56:
		var drop := _sphere(get_parent(), Vector3.ZERO, Vector3(0.027, 0.055, 0.027), foam)
		drop.visible = false
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		splash_pool.append({"node":drop, "life":0.0, "velocity":Vector3.ZERO})
	for i in 8:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.94
		torus.outer_radius = 1.0
		torus.rings = 36
		torus.ring_segments = 4
		var ring := _mesh(get_parent(), torus, Vector3.ZERO, foam)
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_rings.append({"node":ring, "life":0.0, "strength":1.0})

func _fin(parent: Node3D, a: Vector3, b: Vector3, c: Vector3, mat: Material) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := (b-a).cross(c-a).normalized()
	for point in [a,b,c]:
		mesh.surface_set_normal(normal)
		mesh.surface_add_vertex(point)
	for point in [c,b,a]:
		mesh.surface_set_normal(-normal)
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_mesh(parent, mesh, Vector3.ZERO, mat)

func _splash(at: Vector3, count: int, strength: float) -> void:
	var emitted := 0
	for entry: Dictionary in splash_pool:
		if float(entry.life) > 0: continue
		var angle := float(emitted) * 2.39996 + elapsed
		var node: MeshInstance3D = entry.node
		node.global_position = at + Vector3(sin(angle), 0, cos(angle)) * 0.12
		node.visible = true
		entry.life = 0.45 + float(emitted % 4) * 0.09
		entry.velocity = Vector3(sin(angle) * 1.2, 1.7 + float(emitted % 3) * 0.45, cos(angle) * 1.2) * strength
		emitted += 1
		if emitted >= count: break
	for entry: Dictionary in water_rings:
		if float(entry.life) > 0: continue
		entry.life = 1.0
		entry.strength = strength
		entry.node.global_position = Vector3(at.x, 0.11, at.z)
		entry.node.visible = true
		break

func _animate_fishing_visuals(dt: float) -> void:
	bobber.visible = line_active and not waiting_cast and landing_time < 0
	bobber_dip = maxf(0, bobber_dip - dt)
	if bobber.visible:
		var bobber_at := line_target
		bobber_at.y = 0.13 + sin(elapsed * 5.5) * 0.025 - sin(bobber_dip / 0.65 * PI) * 0.16
		if cast_animation >= 0:
			cast_animation += dt
			var cast_t := minf(1, cast_animation / 0.55)
			bobber_at = cast_start.lerp(bobber_at, cast_t) + Vector3.UP * sin(cast_t * PI) * 1.3
			if cast_t >= 1:
				cast_animation = -1
				_splash(line_target, 10, 0.65)
		bobber.global_position = bobber_at
		bobber.rotation.z = sin(elapsed * 4) * (0.25 if fish_fighting else 0.08)
	if landing_time >= 0:
		landing_time += dt
		var landing_t := minf(1, landing_time / 1.1)
		hooked_fish.visible = true
		hooked_fish.global_position = landing_start.lerp(global_position + Vector3(0, 1.25, 0), landing_t) + Vector3.UP * sin(landing_t * PI) * 2.2
		hooked_fish.rotation.z = sin(landing_t * TAU * 2) * 0.4
		if landing_t >= 1:
			landing_time = -1
			hooked_fish.visible = false
	else:
		hooked_fish.visible = line_active and fish_fighting
		if hooked_fish.visible:
			var desired := line_target + Vector3(sin(elapsed * 3) * 0.28, 0, cos(elapsed * 2.1) * 0.3)
			desired.y = 0.10 + absf(sin(elapsed * (9 if fish_surge else 3))) * (0.45 if fish_surge else 0.11)
			var travel := desired - hooked_fish.global_position
			hooked_fish.global_position = hooked_fish.global_position.lerp(desired, minf(1, dt * 10))
			if Vector2(travel.x, travel.z).length() > 0.005:
				hooked_fish.rotation.y = lerp_angle(hooked_fish.rotation.y, atan2(travel.x, travel.z), minf(1, dt * 6))
			hooked_fish.rotation.z = sin(elapsed * 7) * (0.55 if fish_surge else 0.18)
			hooked_fish.rotation.x = sin(elapsed * 8) * (0.25 if fish_surge else 0.05)
			splash_timer -= dt
			if splash_timer <= 0:
				splash_timer = 0.26 if fish_surge else 1.15
				_splash(desired, 6 if fish_surge else 3, 0.8 if fish_surge else 0.32)
	fish_tail.rotation.y = sin(elapsed * (22 if fish_surge else 12)) * 0.6
	for entry: Dictionary in splash_pool:
		if float(entry.life) <= 0: continue
		entry.life = float(entry.life) - dt
		entry.velocity += Vector3.DOWN * dt * 6
		entry.node.global_position += entry.velocity * dt
		entry.node.visible = float(entry.life) > 0 and entry.node.global_position.y > 0.04
	for entry: Dictionary in water_rings:
		if float(entry.life) <= 0: continue
		entry.life = float(entry.life) - dt
		var size := (1.0 - float(entry.life)) * 1.3 * float(entry.strength) + 0.13
		entry.node.scale = Vector3(size, 0.2, size)
		entry.node.visible = float(entry.life) > 0

func _bend_rod() -> void:
	var bend := clampf(line_tension, 0, 1) if fishing else 0.0
	var previous := Vector3.ZERO
	for i in rod_segments.size():
		var t := float(i + 1) / float(rod_segments.size())
		var point := Vector3(0, t * 1.65 - t * t * (0.22 + bend * 0.70), t * 0.78 + t * t * (0.33 + bend * 0.75))
		var node := rod_segments[i]
		var direction := (point - previous).normalized()
		var reference := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		var x_axis := reference.cross(direction).normalized()
		node.position = (previous + point) / 2
		node.basis = Basis(x_axis, direction, x_axis.cross(direction).normalized())
		(node.mesh as CylinderMesh).height = previous.distance_to(point)
		previous = point
	rod_tip.position = previous

func _build_sailor() -> void:
	model = _group(self, Vector3.ZERO)
	var jacket := _material("ochre", Color("ac813c"))
	var trim := _material("trim", Color("d3a15a"))
	var navy := _material("navy", Color("304c59"))
	var skin := _material("skin", Color("dca980"))
	var hair := _material("hair", Color("302b26"))
	var boot := _material("boot", Color("6c5140"))
	torso = _group(model, Vector3(0, 0.92, 0))
	_sphere(torso, Vector3(0, 0.28, 0), Vector3(0.29, 0.37, 0.21), jacket)
	_box(torso, Vector3(0, 0.29, 0.19), Vector3(0.027, 0.52, 0.02), trim)
	for side in [-1, 1]:
		_box(torso, Vector3(side * 0.15, 0.15, 0.195), Vector3(0.15, 0.1, 0.025), trim)
	_sphere(torso, Vector3(0, 0.56, -0.045), Vector3(0.24, 0.14, 0.2), trim)
	_sphere(torso, Vector3(0, 0.78, 0.005), Vector3(0.21, 0.255, 0.19), skin)
	_sphere(torso, Vector3(0, 0.87, -0.04), Vector3(0.222, 0.21, 0.183), hair)
	for i in 9:
		var angle := float(i) * 2.4
		_sphere(torso, Vector3(sin(angle) * 0.17, 0.98 + sin(i * 2.2) * 0.04, cos(angle) * 0.13 - 0.025), Vector3(0.08, 0.075, 0.08), hair)
	_sphere(torso, Vector3(0, 0.77, 0.187), Vector3(0.045, 0.055, 0.048), skin)
	for side in [-1, 1]:
		_sphere(torso, Vector3(side * 0.075, 0.805, 0.174), Vector3(0.018, 0.017, 0.014), hair)
	for side in [-1, 1]:
		var hip := _group(model, Vector3(side * 0.13, 0.9, 0))
		_capsule(hip, Vector3(0, -0.21, 0), 0.115, 0.44, navy)
		var knee := _group(hip, Vector3(0, -0.40, 0))
		_capsule(knee, Vector3(0, -0.17, 0), 0.092, 0.38, navy)
		_box(knee, Vector3(0, -0.40, 0.05), Vector3(0.2, 0.16, 0.31), boot)
		knees.append(knee)
		limbs.append(hip)
	for side in [-1, 1]:
		var shoulder := _group(torso, Vector3(side * 0.27, 0.49, 0))
		_capsule(shoulder, Vector3(side * 0.015, -0.16, 0), 0.1, 0.37, jacket)
		_capsule(shoulder, Vector3(side * 0.02, -0.39, 0.075), 0.083, 0.24, jacket).rotation.x = -0.6
		_sphere(shoulder, Vector3(side * 0.02, -0.49, 0.13), Vector3(0.072, 0.085, 0.07), skin)
		limbs.append(shoulder)
	rod = _group(model, Vector3(0.32, 1.02, 0.28))
	var bamboo := _material("bamboo", Color("846338"))
	var previous := Vector3.ZERO
	for i in range(1, 12):
		var t := float(i) / 11
		var point := Vector3(0, t * 1.65 - t * t * 0.22, t * 0.78 + t * t * 0.33)
		rod_segments.append(_segment(rod, previous, point, 0.022 - t * 0.012, bamboo))
		previous = point
	rod_tip = _group(rod, previous)
	_sphere(rod, Vector3(-0.06, 0.16, 0.06), Vector3(0.075, 0.07, 0.07), navy)

func _build_boat() -> void:
	boat = _group(get_parent(), Vector3(3, 0.35, 7))
	boat.name = "FirstLightBoat"
	var cream := _material("hull", Color("e4d5af"))
	var green := _material("gunwale", Color("497e76"))
	var wood := _material("cedar", Color("b28b5c"))
	var dark := _material("timber", Color("775b3d"))
	var metal := _material("motor", Color("465766"))
	# Swept planks make a pointed bow and rounded belly, all generated locally.
	var sections := [Vector2(-1.65, 0.65), Vector2(-1.2, 0.84), Vector2(-0.5, 0.93), Vector2(0.4, 0.9), Vector2(1.1, 0.65), Vector2(1.8, 0.06)]
	for side in [-1, 1]:
		for i in range(sections.size() - 1):
			var a: Vector2 = sections[i]
			var b: Vector2 = sections[i + 1]
			for plank in 4:
				var y := -0.13 + plank * 0.17
				var spread := 0.72 + plank * 0.085
				var start := Vector3(a.y * side * spread, y, a.x)
				var end := Vector3(b.y * side * spread, y + (0.06 if i > 3 else 0.0), b.x)
				var board_mesh := _box(boat, (start + end) / 2, Vector3(0.065, 0.158, start.distance_to(end) + 0.035), cream)
				board_mesh.rotation.y = atan2(end.x - start.x, end.z - start.z)
			_segment(boat, Vector3(a.y * side, 0.49, a.x), Vector3(b.y * side, 0.49 + (0.06 if i > 3 else 0), b.x), 0.055, green)
	for i in 12:
		var z := -1.42 + i * 0.235
		var width := 1.3 if z < 0.7 else 1.3 - (z - 0.7) * 0.75
		_box(boat, Vector3(0, -0.08, z), Vector3(width, 0.09, 0.22), wood)
	for z in [-1.25, 0.5, 1.1]:
		_box(boat, Vector3(0, 0.27, z), Vector3(1.38 if z < 1 else 1.0, 0.095, 0.3), wood)
	_box(boat, Vector3(0, 0.09, -1.65), Vector3(1.31, 0.53, 0.075), cream)
	_box(boat, Vector3(0, 0.49, -1.65), Vector3(1.4, 0.09, 0.12), green)
	_box(boat, Vector3(0, 0.43, -1.82), Vector3(0.4, 0.4, 0.42), metal)
	_box(boat, Vector3(0, -0.02, -1.86), Vector3(0.12, 0.7, 0.16), metal)
	_box(boat, Vector3(0, -0.3, -1.9), Vector3(0.38, 0.07, 0.1), metal)
	_segment(boat, Vector3(0.08, 0.52, -1.7), Vector3(0.38, 0.5, -1.24), 0.035, dark)
	for side in [-1, 1]:
		_segment(boat, Vector3(side * 0.8, 0.55, -1.0), Vector3(side * 0.83, 0.59, 1.15), 0.03, wood)
		_box(boat, Vector3(side * 0.83, 0.59, 1.0), Vector3(0.12, 0.045, 0.4), wood)
		_sphere(boat, Vector3(side * 0.98, 0.22, -0.7), Vector3(0.13, 0.22, 0.13), cream)
	# A slatted catch crate and coiled rope make the working boat readable.
	for i in 4:
		_box(boat, Vector3(0.45, 0.01 + i * 0.09, 0.18), Vector3(0.46, 0.065, 0.035), dark)
		_box(boat, Vector3(0.45, 0.01 + i * 0.09, -0.27), Vector3(0.46, 0.065, 0.035), dark)
		for x in [0.23, 0.67]: _box(boat, Vector3(x, 0.01 + i * 0.09, -0.045), Vector3(0.035, 0.065, 0.46), wood)
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.09 + i * 0.025
		ring.outer_radius = 0.11 + i * 0.025
		ring.rings = 16
		ring.ring_segments = 6
		_mesh(boat, ring, Vector3(-0.35, 0.06 + i * 0.015, 0.9), cream)

func _material(key: String, color: Color, unshaded := false) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.metallic_specular = 0.25
	if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

func _group(parent: Node, at: Vector3) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = at
	return node

func _mesh(parent: Node, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	parent.add_child(node)
	node.position = at
	return node

func _box(parent: Node, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, mat)

func _sphere(parent: Node, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 12
	mesh.rings = 8
	var node := _mesh(parent, mesh, at, mat)
	node.scale = size
	return node

func _capsule(parent: Node, at: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 5
	return _mesh(parent, mesh, at, mat)

func _segment(parent: Node, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	var node := _mesh(parent, mesh, (a + b) / 2, mat)
	var direction := (b - a).normalized()
	var reference := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var x_axis := reference.cross(direction).normalized()
	node.basis = Basis(x_axis, direction, x_axis.cross(direction).normalized())
	return node
