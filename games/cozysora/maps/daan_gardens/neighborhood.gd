extends RefCounted
## A walk-in café street under tiled apartments, with locally authored façade details.
var map
var g
var rng = RandomNumberGenerator.new()
var origin: Vector3
var turn = Basis(Vector3.UP, -PI * .5)


func build(world, geometry) -> void:
	map = world
	g = geometry
	rng.seed = 80526
	var names = [
		"MORNING TEA",
		"LEAF & CUP",
		"PARK BOOKS",
		"AFTER RAIN",
		"LITTLE BAKERY",
		"SUMMER TABLE",
		"GREEN CORNER",
		"SLOW AFTERNOON"
	]
	for i in range(8):
		_building(Vector3(108 + (i % 3) * .35, 1.2, -81 + i * 23), 12. + i % 3, 3 + i % 3, i, names[i])
	for cluster in range(5):
		var z = -88. + cluster * 38
		for i in range(3 if cluster % 2 == 0 else 2):
			_scooter(Vector3(92.3 + (i % 2) * .2, 1.27, z + i * 1.4), -.18 + i * .14, cluster + i)
		g.box(Vector3(92.3, 1.28, z + 1.4), Vector3(.08, .012, 6.2), "b9b991")
	for i in range(7):
		_service_court(Vector3(108, 1.2, -69.5 + i * 23), i)
	for z in [-90., -38., 8., 57., 94.]:
		g.add("cylinder", Vector3(79, 3.2, z), Vector3(.13, 4, .13), "6f8278", Vector3.ZERO, true)
		g.beam(Vector3(79, 5.1, z), Vector3(81, 5.1, z), .055, "6f8278")
		g.box(Vector3(81, 5.03, z), Vector3(.8, .13, .32), "c7c8ab")
	# Back alleys and pale distant buildings anchor the park inside an inhabited city.
	g.box(Vector3(120, 1.21, 0), Vector3(8, .025, 237), "8f9487")
	g.box(Vector3(15, 1.17, -129), Vector3(290, .05, 15), "89978c")
	g.box(Vector3(15, 1.17, 128), Vector3(290, .05, 15), "89978c")
	for i in range(32):
		var x = 143. + (i % 3) * 15.
		var z = -161. + i * 10.5
		var h = rng.randf_range(13, 35)
		_sky_building(Vector3(x, 1.2, z), Vector3(12, h, 13), i)
	for i in range(20):
		var x = -144. + i * 15
		_sky_building(Vector3(x, 1.2, -153 - rng.randf_range(0, 20)), Vector3(11, rng.randf_range(15, 29), 13), i)
		_sky_building(Vector3(x, 1.2, 153 + rng.randf_range(0, 20)), Vector3(12, rng.randf_range(15, 27), 12), i + 2)


func _at(p: Vector3) -> Vector3:
	return origin + turn * p


func _box(p: Vector3, size: Vector3, color: String, solid: bool = false, finish: int = 0) -> void:
	g.box(_at(p), size, color, solid, -PI * .5, finish)


func _building(p: Vector3, w: float, floors: int, index: int, title: String) -> void:
	origin = p
	var tile = ["b2baa5", "b4a794", "9eafa5", "b5b89f"][index % 4]
	var accent = ["698574", "8c8270", "6f8790", "8e986e"][index % 4]
	var h = 3.5 + floors * 2.8
	# Side and rear walls leave the recessed ground floor and central café door accessible.
	_box(Vector3(0, h * .5, -5.8), Vector3(w, h, .35), tile, true, 2)
	for side in [-1, 1]:
		_box(Vector3(side * (w * .5 - .14), h * .5, 0), Vector3(.28, h, 12), tile, true, 2)
	_box(Vector3(0, (h + 3.3) * .5, 0), Vector3(w, h - 3.3, 12), tile, true, 2)
	_box(Vector3(0, .025, 0), Vector3(w, .05, 12), "b2ae96", false, 1)
	_box(Vector3(0, 3.25, 0), Vector3(w, .16, 12.2), "b6bba7", true)
	for x in [-w * .5 + 1.5, w * .5 - 1.5]:
		_box(Vector3(x, 1.5, 5.87), Vector3(2.8, 2.7, .08), "506e69", true)
		for dx in [-1.4, 0, 1.4]:
			_box(Vector3(x + dx, 1.5, 5.96), Vector3(.07, 2.8, .06), "c4c7b0")
		_box(Vector3(x, 1.48, 5.96), Vector3(2.8, .065, .06), "c4c7b0")
	for side in [-1, 1]:
		_box(Vector3(side * 1.35, 1.4, 5.95), Vector3(.14, 2.8, .16), accent, true)
	_box(Vector3(0, 2.85, 5.93), Vector3(2.8, .14, .18), accent, true)
	_box(Vector3(0, .025, 7.5), Vector3(w, .05, 3.3), "b2ae96", false, 1)
	for x in [-3.7, 3.7]:
		_table(Vector3(x, 0, 2.0))
		_box(Vector3(x, 2.85, 1.5), Vector3(.035, .6, .035), "73877a")
		g.add("cylinder", _at(Vector3(x, 2.49, 1.5)), Vector3(.62, .16, .62), "d3bd91")
	# Interior fixtures remain visible through the open doorway.
	_box(Vector3(0, .48, -2.9), Vector3(5, .96, 1.1), "9b8d6c", true, 3)
	_box(Vector3(0, 1.0, -2.9), Vector3(5.2, .09, 1.25), "cec3a0")
	for x in [-1.5, 0, 1.5]:
		g.add("cylinder", _at(Vector3(x, 1.15, -2.8)), Vector3(.16, .2, .16), "ded8ba")
	for y in [1.1, 1.8, 2.5]:
		_box(Vector3(0, y, -5.35), Vector3(7, .1, .65), accent)
		for j in range(15):
			_box(
				Vector3(-3.2 + j * .45, y + .21, -5.25),
				Vector3(.19, .33, .24),
				["d4bc87", "9ead8b", "b78f75", "839999"][j % 4]
			)
	_box(Vector3(0, 3.05, 6.14), Vector3(w - .3, .48, .18), accent)
	g.label(title, _at(Vector3(0, 3.08, 6.25)), w - 1, "ece1bc", -PI * .5)
	# A striped fabric canopy slopes away from the shop front.
	for stripe in range(int(w / .35)):
		var x = -w * .5 + .175 + stripe * .35
		g.add(
			"box",
			_at(Vector3(x, 2.77, 7.0)),
			Vector3(.35, .045, 1.85),
			accent if stripe % 2 == 0 else "d8d0af",
			Vector3(.13, -PI * .5, 0)
		)
		_box(Vector3(x, 2.63, 7.92), Vector3(.35, .2, .04), accent if stripe % 2 == 0 else "d8d0af")
	for x in [-w * .5 + .3, w * .5 - .3]:
		g.beam(_at(Vector3(x, 2.1, 6.1)), _at(Vector3(x, 2.65, 7.8)), .025, accent)
	# Balcony slabs, barred windows, AC boxes and hanging plants vary per apartment.
	for floor in range(floors):
		var y = 4.65 + floor * 2.8
		for bay in range(3):
			var x = (bay - 1) * (w / 3.)
			_box(Vector3(x, y, 6.015), Vector3(2.4, 1.7, .055), "527471")
			for dx in [-1.25, 0, 1.25]:
				_box(Vector3(x + dx, y, 6.065), Vector3(.07, 1.85, .085), "c5c9b4")
			for dy in [-.92, 0, .92]:
				_box(Vector3(x, y + dy, 6.07), Vector3(2.58, .06, .09), "c5c9b4")
			if (floor + bay + index) % 3 != 0:
				_box(Vector3(x, y - .94, 6.52), Vector3(3.0, .13, 1.2), accent, true)
				for j in range(9):
					_box(Vector3(x - 1.4 + j * .35, y - .43, 7.08), Vector3(.035, 1, .035), "a6b6a4")
				for level in [y - .91, y + .09]:
					_box(Vector3(x, level, 7.08), Vector3(2.9, .045, .045), "adb9a5")
				for side in [-1, 1]:
					_box(Vector3(x + side * 1.43, y - .43, 6.53), Vector3(.035, 1, 1.1), "a6b6a4")
				_planter(Vector3(x + .7, y - .66, 6.6), .65)
			else:
				for j in range(7):
					_box(Vector3(x - 1.1 + j * .37, y, 6.16), Vector3(.025, 1.75, .04), "92a591")
				_box(Vector3(x, y - .57, 6.19), Vector3(2.5, .03, .04), "92a591")
			_box(Vector3(x + 1.48, y + .1, 6.23), Vector3(.48, .56, .43), "c2c2aa")
			for j in range(4):
				_box(Vector3(x + 1.48, y - .07 + j * .1, 6.46), Vector3(.36, .025, .025), "8d9d90")
	# Both side elevations have small windows and rain streaks, visible from the side courts.
	for side in [-1, 1]:
		for floor in range(floors):
			var y = 4.65 + floor * 2.8
			for z in [-3.5, .0, 3.5]:
				_box(Vector3(side * (w * .5 + .03), y, z), Vector3(.07, 1.4, 1.6), "628077")
				for dz in [-.85, 0, .85]:
					_box(Vector3(side * (w * .5 + .08), y, z + dz), Vector3(.06, 1.5, .05), "b9c2a9")
				for dy in [-.76, .76]:
					_box(Vector3(side * (w * .5 + .08), y + dy, z), Vector3(.06, .055, 1.75), "b9c2a9")
	# Usable flat roof, parapets, a water tank and utility pipework.
	_box(Vector3(0, h + .08, 0), Vector3(w + .15, .16, 12.2), "a2ac97", true)
	for z in [-5.9, 5.9]:
		_box(Vector3(0, h + .5, z), Vector3(w, .85, .17), tile, true, 2)
	for x in [-w * .5, w * .5]:
		_box(Vector3(x, h + .5, 0), Vector3(.17, .85, 12), tile, true, 2)
	_box(Vector3(-2, h + .33, -2), Vector3(2.3, .5, 2.3), accent, true)
	g.add("cylinder", _at(Vector3(-2, h + 1.6, -2)), Vector3(1.9, 2.1, 1.9), "bfc5b2", Vector3.ZERO, true)
	for y in [h + .67, h + 1.5, h + 2.5]:
		g.add("cylinder", _at(Vector3(-2, y, -2)), Vector3(1.98, .065, 1.98), "8d9f94")
	g.beam(_at(Vector3(-.9, h + .25, -2)), _at(Vector3(-.9, h + 1.5, -2)), .06, "81988d")
	for k in range(4):
		_planter(Vector3(2 + k * .65, h + .32, 3.6), .5)
	# Two café tables outside flank a generous clear route to the doorway.
	for x in [-3.4, 3.4]:
		_table(Vector3(x, 0, 8.3))
		_planter(Vector3(x * .48, .32, 6.7), .7)
	_box(Vector3(-w * .5 - .25, 2.15, 6.25), Vector3(.55, 2.2, .3), accent)
	g.label("TEA\n&\nCOFFEE", _at(Vector3(-w * .5 - .25, 2.2, 6.42)), .44, "e4dab9", -PI * .5)
	# Rainwater pipe and a wall-mounted meter create detail at cat height.
	g.beam(_at(Vector3(w * .5 - .35, .15, 6.1)), _at(Vector3(w * .5 - .35, h - .5, 6.1)), .06, "8d9e8b")
	_box(Vector3(w * .5 - .64, 1.25, 6.13), Vector3(.34, .5, .15), "8a9f91")


func _planter(p: Vector3, s: float) -> void:
	g.add("cylinder", _at(p), Vector3(s, .55, s), "a29475")
	for j in range(6):
		var a = j * 2.399
		g.add(
			"sphere",
			_at(p + Vector3(cos(a) * s * .3, .43 + sin(j) * .09, sin(a) * s * .3)),
			Vector3(s * .5, .5, s * .4),
			"7c9461"
		)


func _table(p: Vector3) -> void:
	g.add("cylinder", _at(p + Vector3(0, .38, 0)), Vector3(.15, .76, .15), "6d8373")
	g.add("cylinder", _at(p + Vector3(0, .78, 0)), Vector3(.9, .08, .9), "b6a680", Vector3.ZERO, true)
	g.add("cylinder", _at(p + Vector3(0, .88, 0)), Vector3(.13, .15, .13), "e3dcc1")
	for x in [-.7, .7]:
		_box(p + Vector3(x, .45, 0), Vector3(.4, .07, .4), "8e9b79", true)
		for dx in [-.16, .16]:
			for dz in [-.16, .16]:
				_box(p + Vector3(x + dx, .23, dz), Vector3(.04, .46, .04), "657c6d")
		_box(p + Vector3(x, .72, -.18), Vector3(.42, .42, .05), "8e9b79")


func _scooter(p: Vector3, yaw: float, index: int) -> void:
	var basis = Basis(Vector3.UP, yaw)
	for z in [-.48, .48]:
		g.add("cylinder", p + basis * Vector3(0, .25, z), Vector3(.48, .13, .48), "414e48", Vector3(0, yaw, PI * .5))
		g.add("cylinder", p + basis * Vector3(0, .25, z), Vector3(.26, .15, .26), "98a797", Vector3(0, yaw, PI * .5))
	var color = ["929f85", "b3987e", "839ea0", "c2bd99"][index % 4]
	g.box(p + basis * Vector3(0, .46, .05), Vector3(.48, .35, .95), color, true, yaw)
	g.box(p + basis * Vector3(0, .7, -.16), Vector3(.45, .11, .62), "59655b", false, yaw)
	g.box(p + basis * Vector3(0, .71, .42), Vector3(.48, .56, .17), color, false, yaw)
	g.beam(p + basis * Vector3(-.33, 1, .41), p + basis * Vector3(.33, 1, .41), .035, "697c6e")
	g.box(p + basis * Vector3(0, .87, .52), Vector3(.2, .15, .03), "e2d9b3", false, yaw)
	for side in [-1, 1]:
		g.beam(p + basis * Vector3(side * .25, 1, .4), p + basis * Vector3(side * .34, 1.22, .42), .012, "829689")
		g.add(
			"sphere", p + basis * Vector3(side * .34, 1.24, .42), Vector3(.15, .09, .04), "aec0af", Vector3(0, yaw, 0)
		)


func _sky_building(p: Vector3, size: Vector3, index: int) -> void:
	var color = ["9bac9d", "aeb7a1", "93a89e"][index % 3]
	g.box(p + Vector3(0, size.y * .5, 0), size, color)
	g.box(p + Vector3(0, size.y + .4, 0), Vector3(size.x + .3, .5, size.z + .3), color)
	for y in range(3, int(size.y) - 1, 3):
		for z in [-size.z * .5 - .025, size.z * .5 + .025]:
			for x in range(-4, 5, 3):
				g.box(p + Vector3(x, y, z), Vector3(1.4, 1.4, .05), "7e9b91")
		for z in range(-4, 5, 3):
			g.box(p + Vector3(-size.x * .5 - .025, y, z), Vector3(.05, 1.4, 1.5), "7e9b91")


func _service_court(p: Vector3, index: int) -> void:
	# A side passage meets the café sidewalk and leads to a shared bicycle courtyard.
	origin = p
	_box(Vector3(0, .02, 1), Vector3(7, .04, 11), "a6ad96", false, 1)
	_box(Vector3(0, 1.0, -3.6), Vector3(7, 2, .18), "8e9e85", true, 2)
	for x in [-2.3, 0, 2.3]:
		_box(Vector3(x, 1.2, 3.6), Vector3(.11, 2.4, .11), "7f9378", true)
	for z in [-1., 1., 3., 4.8]:
		_box(Vector3(0, 2.4, z), Vector3(7, .09, .11), "8a987a")
	for x in [-3., -1.5, 0, 1.5, 3.]:
		_box(Vector3(x, 2.42, 1.8), Vector3(.1, .1, 6.4), "8a987a")
	for x in [-2.8, 2.8]:
		_planter(Vector3(x, .4, 4.8), 1.1)
		_box(Vector3(x, .4, -2.4), Vector3(1.6, .8, .65), "9d9d7d", true)
	for i in range(4):
		var x = -2.2 + i * 1.45
		g.beam(_at(Vector3(x, 0, -.5)), _at(Vector3(x, .6, -.5)), .03, "6e8877")
		g.beam(_at(Vector3(x, .6, -.5)), _at(Vector3(x, .6, -1.5)), .03, "6e8877")
		g.beam(_at(Vector3(x, .6, -1.5)), _at(Vector3(x, 0, -1.5)), .03, "6e8877")
	# A chalkboard and a pair of stacked crates sit beside, rather than in, the passage.
	_box(Vector3(2.4, .62, 6.6), Vector3(.72, 1.24, .1), "63816b", true)
	g.label("TEA\n& A LITTLE\nTIME", _at(Vector3(2.4, .73, 6.67)), .58, "ddd5ae", -PI * .5)
	for i in range(2):
		_box(Vector3(-2.5, .2 + i * .38, 6.5), Vector3(.75, .36, .6), "a99a74", true, 3)
