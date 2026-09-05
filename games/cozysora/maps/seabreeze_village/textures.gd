extends RefCounted
## Seabreeze texture recipes: seeds, colors and plant silhouettes stay map-owned.


static func leaf_texture(seed_value: int, small: bool = false) -> Texture2D:
	var random := SeabreezeRandom.new()
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
			var shade: float = (
				random.randf_range(0.47, 0.67) if pass_index == 0 else random.randf_range(0.63, 1) - radius / 77 * 0.10
			)
			CozyLeafPainter.paint(
				image, p, length, width, rotation, shade, CozyLeafPainter.Profile.ROUNDED, pass_index == 1
			)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func bark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a3a2c")
	material.roughness = 1
	var image := Image.create(64, 256, false, Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(64):
			var stripe: float = sin(x * 1.3 + sin(y * 0.025) * 1.7) * 0.09 + sin(x * 3.4 + y * 0.04) * 0.055
			image.set_pixel(x, y, Color(0.82 + stripe, 0.78 + stripe, 0.72 + stripe))
	image.generate_mipmaps()
	material.albedo_texture = ImageTexture.create_from_image(image)
	return material


static func flower_texture(color: Color, seed_value: int) -> Texture2D:
	var random := SeabreezeRandom.new()
	random.seed = seed_value
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in range(5):
		var x: int = random.randi_range(40, 216)
		var y: int = random.randi_range(40, 128)
		for sy in range(y, 256):
			for sx in range(-2, 3):
				image.set_pixel(clampi(x + sx + int(sin(sy * 0.025 + i) * 5), 0, 255), sy, Color("5b7c32"))
		for petal in range(random.randi_range(5, 9)):
			var px: int = x + random.randi_range(-14, 14)
			var py: int = y + random.randi_range(-12, 12)
			var radius: int = random.randi_range(5, 9)
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if dx * dx + dy * dy <= radius * radius:
						image.set_pixel(px + dx, py + dy, color)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy < 10:
					image.set_pixel(x + dx, y + dy, Color("ffd54a"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func pine_needle_texture() -> Texture2D:
	var random := SeabreezeRandom.new()
	random.seed = 79
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for cluster in range(70):
		var angle: float = random.randf() * TAU
		var radius: float = sqrt(random.randf()) * 153.6
		var center := Vector2(256 + cos(angle) * radius, 256 + sin(angle) * radius)
		var shade: float = (120 + floorf(random.randf() * 110) - floorf(radius / 153.6 * 30)) / 255
		var count: int = random.randi_range(9, 14)
		var direction: float = random.randf() * TAU
		for needle in range(count):
			var theta: float = direction + (float(needle) / count - 0.5) * 2.2
			var length: float = random.randf_range(26, 56)
			paint_stroke(
				image, center, center + Vector2(cos(theta), sin(theta)) * length, 3, Color(shade, shade, shade)
			)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func paint_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in range(maxi(0, floori(center.y - radius)), mini(image.get_height(), ceili(center.y + radius) + 1)):
		for x in range(maxi(0, floori(center.x - radius)), mini(image.get_width(), ceili(center.x + radius) + 1)):
			if Vector2(x, y).distance_squared_to(center) <= radius * radius:
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))


static func paint_stroke(image: Image, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	var steps: int = maxi(1, ceili(start.distance_to(end)))
	for i in range(steps + 1):
		paint_disc(image, start.lerp(end, float(i) / steps), width * 0.5, color)


static func paint_ellipse(image: Image, center: Vector2, radii: Vector2, color: Color) -> void:
	for y in range(maxi(0, floori(center.y - radii.y)), mini(image.get_height(), ceili(center.y + radii.y) + 1)):
		for x in range(maxi(0, floori(center.x - radii.x)), mini(image.get_width(), ceili(center.x + radii.x) + 1)):
			if ((Vector2(x, y) - center) / radii).length_squared() <= 1:
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))


static func shrine_flower_texture(kind: String, seed_value: int) -> Texture2D:
	var random := SeabreezeRandom.new()
	random.seed = seed_value
	var image := Image.create(128, 384, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if kind == "aster":
		for i in range(2 + int(random.randf() < 0.5)):
			var center := Vector2(40 + (i % 2) * 48 + random.randf_range(-6, 6), 40 + i * 66 + random.randf() * 24)
			var radius: float = random.randf_range(31, 36)
			var petals: int = random.randi_range(12, 14)
			var phase: float = random.randf() * PI
			for petal in range(petals):
				var angle: float = float(petal) / petals * TAU + phase
				var length: float = radius * random.randf_range(0.88, 1.02)
				paint_stroke(image, center, center + Vector2(cos(angle), sin(angle)) * length, 12, Color("a894d2"))
			paint_disc(image, center, radius * 0.62, Color("a894d2"))
			paint_disc(image, center, 11, Color("e6bc4e"))
		paint_ellipse(
			image, Vector2(random.randf_range(40, 88), random.randf_range(210, 260)), Vector2(10, 14), Color("9a86c6")
		)
	elif kind == "buttercup":
		for stalk in range(2):
			var x: float = 34 + stalk * 60 + random.randf_range(-7, 7)
			var y: float = random.randf_range(44, 114)
			for bloom in range(2 + int(random.randf() < 0.5)):
				paint_disc(
					image,
					Vector2(x + random.randf_range(-11, 11), y + bloom * random.randf_range(36, 48) - 4),
					random.randf_range(21, 24),
					Color("eeae36")
				)
	else:
		for stalk in range(2):
			var center := Vector2(32 + stalk * 64 + random.randf_range(-8, 8), random.randf_range(44, 104))
			for petal in range(6):
				paint_disc(
					image,
					center + Vector2(random.randf_range(-11, 11), random.randf_range(-11, 11)),
					random.randf_range(13, 18),
					Color("dd4b56")
				)
	return ImageTexture.create_from_image(image)


static func giant_bark_material(origin: Vector3) -> ShaderMaterial:
	var random := SeabreezeRandom.new()
	random.seed = 21
	var image := Image.create(128, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color8(118, 118, 108))
	for i in range(140):
		var change: int = random.randi_range(-30, 19)
		var color := Color(
			(118 + change) / 255.0, (118 + change) / 255.0, (108 + change) / 255.0, random.randf_range(0.35, 0.75)
		)
		var rect := Rect2i(
			random.randi_range(0, 127),
			random.randi_range(0, 511),
			random.randi_range(2, 7),
			random.randi_range(30, 150)
		)
		for y in range(rect.position.y, mini(512, rect.end.y)):
			for x in range(rect.position.x, mini(128, rect.end.x)):
				image.set_pixel(x, y, image.get_pixel(x, y).blend(color))
	for i in range(60):
		var p := Vector2(random.randf() * 128, random.randf() * 512)
		paint_stroke(
			image,
			p,
			p + Vector2(0, random.randf_range(20, 100)),
			random.randf_range(1, 3),
			Color(20 / 255.0, 14 / 255.0, 10 / 255.0, random.randf_range(0.25, 0.6))
		)
	for i in range(70):
		paint_ellipse(
			image,
			Vector2(random.randf() * 128, random.randf() * 512),
			Vector2(random.randf_range(4, 14), random.randf_range(8, 34)),
			Color(94 / 255.0, 126 / 255.0, 92 / 255.0, random.randf_range(0.25, 0.6))
		)
	for i in range(30):
		paint_ellipse(
			image,
			Vector2(random.randf() * 128, random.randf() * 512),
			Vector2(random.randf_range(3, 9), random.randf_range(6, 24)),
			Color(158 / 255.0, 156 / 255.0, 142 / 255.0, random.randf_range(0.2, 0.5))
		)
	for pass_index in range(2):
		for i in range(70 if pass_index == 0 else 60):
			var start := Vector2(random.randf() * 128, random.randf() * 512 - 40)
			var length: float = random.randf_range(40, 180)
			var drift: float = random.randf_range(-7, 7)
			var color := (
				Color(152 / 255.0, 152 / 255.0, 136 / 255.0, random.randf_range(0.55, 0.9))
				if pass_index == 0
				else Color(72 / 255.0, 70 / 255.0, 62 / 255.0, random.randf_range(0.6, 0.95))
			)
			var width: float = random.randf_range(2, 4)
			var previous := start
			for step in range(1, 13):
				var t: float = float(step) / 12
				var p := start + Vector2(sin(t * PI) * drift, length * t)
				paint_stroke(image, previous, p, width, color)
				previous = p
	for i in range(4):
		var x: float = (i + 0.3 + random.randf() * 0.5) / 4 * 128
		var previous := Vector2(x, -10)
		for step in range(1, 25):
			var p := Vector2(x + sin(step * 0.21 + i) * 8, step / 24.0 * 532 - 10)
			paint_stroke(image, previous, p, 4, Color(72 / 255.0, 70 / 255.0, 62 / 255.0, 0.9))
			paint_stroke(
				image, previous + Vector2(4, 0), p + Vector2(4, 0), 2, Color(152 / 255.0, 152 / 255.0, 136 / 255.0, 0.5)
			)
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
	material.set_shader_parameter("bark_texture", ImageTexture.create_from_image(image))
	material.set_shader_parameter("tree_origin", origin)
	return material
