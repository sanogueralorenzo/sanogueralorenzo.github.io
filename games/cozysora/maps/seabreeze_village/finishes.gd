extends RefCounted
## Generated building finishes and their palette-specific material cache.
var textures: Dictionary = {}


func surface(kind: String, tint: String) -> StandardMaterial3D:
	var key := kind + tint
	if textures.has(key):
		return textures[key]
	var im := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var base := Color(tint)
	var noise := RandomNumberGenerator.new()
	noise.seed = 417 + kind.hash()
	for y in 128:
		for x in 128:
			var f := noise.randf_range(.94, 1.05)
			if kind == "wood":
				f *= .55 if x % 8 < 1 else 1.0
				f += sin(float(y) * .19 + sin(float(x) * 2.7)) * .035
			elif kind == "pole":
				f *= .88 + sin(float(x) * 2.4) * .08
				if y % 29 < 2:
					f *= .8
			elif kind == "bamboo":
				f *= .55 if y % 4 == 0 else 1.0
				f *= .75 if x % 42 < 2 else 1.0
			elif kind == "metal":
				f *= (.84 + sin(float(x % 8) * PI / 4.0) * .13) * .58
			elif kind == "tile":
				f *= .34 if y % 32 < 6 else 1.0
				f *= .85 + sin(float(x % 16) * PI / 16.0) * .2
			elif kind == "paint":
				f *= .9 + sin(float(x) * .08 + sin(float(y) * .05) * 2) * .05
				if noise.randf() < .025:
					f *= .64
			elif kind == "stone":
				f *= .70 if y % 32 < 2 or (x + (y / 32) * 16) % 48 < 2 else 1.0
			im.set_pixel(x, y, Color(base.r * f, base.g * f, base.b * f))
	if kind == "stone":
		rock_pattern(im, base, noise)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(im)
	mat.roughness = .93
	mat.uv1_scale = Vector3(2, 2, 2)
	textures[key] = mat
	return mat


func rock_pattern(im: Image, base: Color, random: RandomNumberGenerator) -> void:
	im.fill(base * .5)
	for i in 60:
		var x := random.randf_range(-12, 126)
		var y := random.randf_range(-12, 126)
		var width := random.randf_range(11, 28)
		var height := random.randf_range(8, 20)
		var poly := PackedVector2Array(
			[
				Vector2(x, y + height * .3),
				Vector2(x + width * .3, y),
				Vector2(x + width, y + height * .2),
				Vector2(x + width * .9, y + height),
				Vector2(x + width * .2, y + height * .95)
			]
		)
		var color := base * random.randf_range(.85, 1.24)
		for yy in range(maxi(0, int(y)), mini(128, int(y + height) + 1)):
			for xx in range(maxi(0, int(x)), mini(128, int(x + width) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(xx, yy), poly):
					im.set_pixel(xx, yy, color * random.randf_range(.94, 1.03))


func chainlink() -> StandardMaterial3D:
	if not textures.has("chainlink"):
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for yy in 64:
			for xx in 64:
				if abs(xx - yy) < 2 or abs(xx + yy - 63) < 2:
					img.set_pixel(xx, yy, Color("#9eafa5"))
		img.generate_mipmaps()
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = .3
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = .9
		textures["chainlink"] = mat
	return textures["chainlink"]
