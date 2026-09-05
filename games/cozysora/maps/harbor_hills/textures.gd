extends RefCounted


## Seeded brush marks: every leaf spray is painted into a runtime image.
static func leaf_spray() -> Texture2D:
	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var rng = RandomNumberGenerator.new()
	rng.seed = 73421
	for layer in range(2):
		for i in range(64):
			var angle = rng.randf() * TAU
			var radius = sqrt(rng.randf()) * 87
			var center = Vector2(128, 128) + Vector2(cos(angle), sin(angle) * .82) * radius
			var length = rng.randf_range(9, 21)
			var width = length * rng.randf_range(.28, .56)
			var turn = angle + rng.randf_range(-1.2, 1.2)
			var shade = rng.randf_range(.46, .72) if layer == 0 else rng.randf_range(.7, 1.0)
			CozyLeafPainter.paint(image, center, length, width, turn, shade, CozyLeafPainter.Profile.POINTED)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
