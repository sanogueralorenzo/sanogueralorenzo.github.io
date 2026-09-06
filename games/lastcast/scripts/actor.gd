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
var camera_pitch := 0.46
var camera_distance := 10.5
var boat_speed := 0.0
var boat_heading := 0.0
var model: Node3D
var sailor_visuals: Node3D
var visual_reeling := false
var fish_exhaustion := 0.0
var steering_pose := 0.0
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
	camera.fov = 55
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
	var wake_material := ShaderMaterial.new()
	wake_material.shader = load("res://shaders/wake.gdshader")
	wake_node.material_override = wake_material
	wake_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(wake_node)
	_build_fishing_visuals()
	reset_home()

func board() -> void:
	boat_camera_orbit = 0.30
	clear_controls()
	sailing = true
	velocity = Vector3.ZERO
	boat_speed = 0.0
	boat_heading = PI / 2.0
	collision_mask = 0
	position = Vector3(4.3, 0.35, 9)
	boat.visible = true
	boat.position = position
	boat.rotation.y = boat_heading
	model.rotation.y = boat_heading
	camera_distance = 10.8
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
	camera_distance = 10.5
	wake_points.clear()
	set_fishing(false)

func reset_home() -> void:
	landing_time = -1.0
	cast_animation = -1.0
	waiting_cast = false
	fish_fighting = false
	if hooked_fish != null: hooked_fish.hide()
	if bobber != null: bobber.hide()
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
	if not active and landing_time >= 0:
		line_node.visible = true
		return
	if active and not line_active:
		var aim := target-global_position
		cast_bearing=atan2(aim.x,aim.z)
	line_target = target
	line_active = active
	line_node.visible = active or landing_time >= 0
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
		if fishing: fishing_orbit = clampf(fishing_orbit - event.relative.x * 0.005, -1.2 if sailing else 1.05, 1.2 if sailing else 2.25)
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
	if not locked or fishing:
		var orbit_input := float(Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_RIGHT))
		if fishing: fishing_orbit = clampf(fishing_orbit + orbit_input * dt * 1.5, -1.2 if sailing else 1.05, 1.2 if sailing else 2.25)
		elif sailing: boat_camera_orbit += orbit_input * dt * 1.5
		else: camera_yaw += orbit_input * dt * 1.5
		if Input.is_physical_key_pressed(KEY_UP): camera_pitch = maxf(0.2, camera_pitch - dt * 0.6)
		if Input.is_physical_key_pressed(KEY_DOWN): camera_pitch = minf(0.98, camera_pitch + dt * 0.6)
	if sailing:
		_sail(dt)
	else:
		_walk(dt)
	_animate(dt)
	_place_camera(dt / maxf(.001, Engine.time_scale))
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
	if p.x > -13.7 and p.x < -11.5 and p.z > -8.6 and p.z <= -4.0: return true
	if p.x > -14.0 and p.x < -11.2 and p.z > -9.6 and p.z <= -8.6: return true
	if p.x > -21.7 and p.x < 21.7 and p.z > -4.1 and p.z < -0.1: return true
	if p.x > -1.22 and p.x < 1.22 and p.z > -1.0 and p.z < 7.65: return true
	if p.x > -13.22 and p.x < -10.78 and p.z > -1.0 and p.z < 4.68: return true
	return false

func _sail(dt: float) -> void:
	var throttle := 0.0 if locked else (-move_latch.y if toggle_controls else Input.get_axis("lc_down", "lc_up"))
	var turn := 0.0 if locked else (move_latch.x if toggle_controls else Input.get_axis("lc_left", "lc_right"))
	steering_pose = lerpf(steering_pose, turn, minf(1.0, dt * 6.0))
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
	# A fully blocked hull is stationary even with throttle held. Steering still
	# turns at rest; a remaining tangent displacement continues to slide normally.
	var actual_motion := Vector2(next.x-position.x,next.z-position.z)
	if actual_motion.length_squared() < .000000000001:
		boat_speed = 0.0
	position = next
	position.y = 0.35 + sin(elapsed * 1.8) * 0.045 + sin(elapsed * 3.3) * 0.015
	boat.position = position
	boat.rotation = Vector3(sin(elapsed * 1.8) * 0.016, boat_heading, sin(elapsed * 1.45) * 0.025 + turn * boat_speed * 0.006)
	if not fishing: model.rotation.y = lerp_angle(model.rotation.y, boat_heading, minf(1, dt * 9))

func _animate(dt: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if not sailing else 0.0
	gait += dt * speed * 4.8
	var seated := sailing and not fishing and landing_time < 0
	model.position.y = (-0.4 if seated else -.08) if sailing else 0.0
	model.position.x = -sin(boat_heading) * .92 if seated else 0.0
	model.position.z = -cos(boat_heading) * .92 if seated else 0.0
	if sailing:
		model.rotation.x = boat.rotation.x
		model.rotation.z = boat.rotation.z
	else:
		model.rotation.x=0.0;model.rotation.z=0.0
	sailor_visuals.pose(dt,elapsed,gait,speed,seated,fishing,waiting_cast,cast_animation,line_tension,visual_reeling,landing_time,steering_pose)
	if not sailing:
		boat.position.y = 0.35 + sin(elapsed * 1.8) * 0.04
		boat.rotation.z = sin(elapsed * 1.45) * 0.022

func _place_camera(dt: float) -> void:
	var wanted_target := global_position + Vector3(0, 1.35 if not sailing else .70, 0)
	var desired_yaw := boat_heading + PI + boat_camera_orbit if sailing else camera_yaw
	if sailing and not fishing and landing_time < 0: wanted_target += Vector3(sin(boat_heading),0,cos(boat_heading))*2.2
	if (fishing and line_active) or landing_time >= 0:
		desired_yaw = cast_bearing + PI + fishing_orbit * .55
		wanted_target = wanted_target.lerp(line_target + Vector3.UP * 1.0, 0.38)
		# A stable diagonal shows the hands, rod and fish together; compact cues sit below.
		var camera_right := Vector3(cos(desired_yaw), 0, -sin(desired_yaw))
		wanted_target += camera_right * .55
	view_yaw = lerp_angle(view_yaw, desired_yaw, 1.0 - exp(-dt * 3.5)) if camera_ready else desired_yaw
	if not camera_ready:
		look_target = wanted_target
	else:
		look_target = look_target.lerp(wanted_target, 1 - exp(-dt * 10))
	var boat_view := sailing and not fishing and landing_time < 0
	var pitch := clampf(camera_pitch-.19,.10,.90) if boat_view else camera_pitch
	camera.fov = lerpf(camera.fov,62.0 if boat_view else 55.0,1.0-exp(-dt*5.0))
	var offset := Vector3(sin(view_yaw)*cos(pitch),sin(pitch),cos(view_yaw)*cos(pitch))*camera_distance
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
	if (not line_active and landing_time < 0) or waiting_cast: return
	var start := rod_tip.global_position
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 33:
		var t := float(i) / 32
		var endpoint := hooked_fish.to_global(Vector3(0, .01, .51)) if hooked_fish.visible else (bobber.global_position + Vector3.UP * 0.23 if bobber.visible else line_target)
		var point := start.lerp(endpoint, t)
		point.y -= sin(t * PI) * minf(0.55, start.distance_to(endpoint) * 0.025) * (1.0 - line_tension * 0.92)
		line_mesh.surface_add_vertex(point)
	line_mesh.surface_end()

func _draw_wake(dt: float) -> void:
	wake_clock += dt
	if sailing and absf(boat_speed) > 0.6 and wake_clock > 0.10:
		wake_clock = 0
		var stern := position - Vector3(sin(boat_heading), 0, cos(boat_heading)) * 2.08
		stern.y = 0.105
		wake_points.push_front(stern)
		if wake_points.size() > 38: wake_points.pop_back()
	elif wake_clock > 0.10 and not wake_points.is_empty():
		wake_clock = 0
		wake_points.pop_back()
	wake_mesh.clear_surfaces()
	if wake_points.size() < 2: return
	wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, wake_points.size()):
		var a := wake_points[i-1]
		var b := wake_points[i]
		var tangent := (a-b).normalized()
		var side := Vector3(tangent.z,0,-tangent.x)
		var age := float(i)/38.0
		var width := .58 + float(i)*.073
		var foam_width := .035+age*.09
		for sign_value in [-1,1]:
			# Independent short curls vary in offset, length, thickness and opacity.
			# No edge-to-edge strip survives long enough to resemble painted rails.
			for dab in 2:
				var seed := float(i)*3.73+float(dab)*5.19+float(sign_value)*1.37
				if sin(seed*1.73)>.50: continue
				var along := .14+float(dab)*.46+sin(seed)*.08
				var jitter := side*sin(seed*2.1)*(.045+age*.07)
				var center: Vector3=a.lerp(b,along)+side*width*float(sign_value)+jitter
				var length := .025+(sin(seed*.79)*.5+.5)*.072
				var thickness := foam_width*(.20+(sin(seed*2.37)*.5+.5)*.40)
				var alpha := (1.0-age)*(.22+(sin(seed)*.5+.5)*.27)
				_foam_dab(center,tangent,side,length,thickness,alpha,seed)
		# Rounded, feathered bubbles scatter through the propwash, not arrowheads.
		for speck in 6:
			var seed := float(i)*2.41+float(speck)*5.13
			var wave := sin(seed)
			var along := clampf((float(speck)+.4)/6.0+sin(seed*1.73)*.035,0.0,1.0)
			var point := a.lerp(b,along)+side*wave*(.12+age*.40)
			var size := .027+(sin(seed*.73)*.5+.5)*.026
			_foam_dab(point,tangent,side,size*1.35,size*.72,(1.0-age)*.64,seed)
	wake_mesh.surface_end()

func _foam_dab(center: Vector3, tangent: Vector3, side: Vector3, length: float, width: float, alpha: float, seed: float) -> void:
	# Clockwise from above: tangent cross side is +Y, so next-angle comes first.
	# Alpha falls continuously to zero around an irregular rounded perimeter.
	for corner in 8:
		var a := float(corner)/8.0*TAU
		var b := float(corner+1)/8.0*TAU
		var radius_a := .88+sin(a*3.0+seed)*.12
		var radius_b := .88+sin(b*3.0+seed)*.12
		var edge_a := center+(tangent*cos(a)*length+side*sin(a)*width)*radius_a
		var edge_b := center+(tangent*cos(b)*length+side*sin(b)*width)*radius_b
		wake_mesh.surface_set_color(Color(1,1,1,alpha))
		wake_mesh.surface_add_vertex(center)
		wake_mesh.surface_set_color(Color(1,1,1,0))
		wake_mesh.surface_add_vertex(edge_b)
		wake_mesh.surface_add_vertex(edge_a)

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
	_fin(hooked_fish, Vector3(0, 0.17, 0.11), Vector3(0, 0.48, -0.28), Vector3(0, 0.18, -0.38), fin)
	fish_tail = _group(hooked_fish, Vector3(0, 0, -0.51))
	_fin(fish_tail, Vector3(0, 0, 0), Vector3(0, 0.34, -0.38), Vector3(0, 0.0, -0.29), fin)
	_fin(fish_tail, Vector3(0, 0, 0), Vector3(0, -0.34, -0.38), Vector3(0, 0.0, -0.29), fin)
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
		landing_time += dt / maxf(.001, Engine.time_scale)
		var landing_t := minf(1, landing_time / 1.6)
		hooked_fish.visible = true
		# Present the catch almost horizontally outside the sailor's free hand.
		# A large signature tail therefore clears both the deck and the legs.
		var nose := (model.global_transform.basis.x.normalized()+Vector3.UP*.14).normalized()
		var across := Vector3.UP.cross(nose).normalized()
		var hold_basis := Basis(across,nose.cross(across).normalized(),nose)
		hooked_fish.quaternion=hooked_fish.quaternion.slerp(hold_basis.get_rotation_quaternion(),minf(1.0,dt/maxf(.001,Engine.time_scale)*7.0))
		var hand: Vector3 = sailor_visuals.to_global(sailor_visuals.left_hand_position)
		var mouth_offset := hooked_fish.basis * Vector3(0,.01,.51)
		hooked_fish.global_position = landing_start.lerp(hand-mouth_offset,smoothstep(0.0,1.0,landing_t)) + Vector3.UP*sin(landing_t*PI)*.65
		# Keep the secured catch at the hand throughout its result card.
		if landing_t >= 1 and not locked:
			landing_time = -1
			hooked_fish.visible = false
	else:
		hooked_fish.visible = line_active and fish_fighting
		if hooked_fish.visible:
			var desired := line_target + Vector3(sin(elapsed * 3) * 0.15 * (1.0-fish_exhaustion*.6), 0, cos(elapsed * 2.1) * 0.15 * (1.0-fish_exhaustion*.6))
			desired.y = 0.10 + absf(sin(elapsed * (9 if fish_surge else 3))) * (0.40 if fish_surge else 0.065)*(1.0-fish_exhaustion*.4)
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
	fish_tail.rotation.y = sin(elapsed * (22 if fish_surge else 9)) * (0.65 if fish_surge else .32) * (1.0-fish_exhaustion*.35)
	if landing_time >= 0: fish_tail.rotation.y=sin(elapsed*5.0)*.06
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

func _build_sailor() -> void:
	sailor_visuals = preload("res://scripts/actor_visuals.gd").new()
	add_child(sailor_visuals)
	sailor_visuals.build()
	model = sailor_visuals
	torso = sailor_visuals.body
	rod = sailor_visuals.rod
	rod_tip = sailor_visuals.rod_tip

func _build_boat() -> void:
	boat = sailor_visuals.build_skiff(get_parent())

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
