class_name CozyLeafPainter
extends RefCounted
## Two authored leaf silhouettes share clipping and rasterization. No random draws.
enum Profile { ROUNDED, POINTED }


static func paint(
	image: Image,
	center: Vector2,
	length: float,
	width: float,
	angle: float,
	shade: float,
	profile: Profile,
	outline: bool = false
) -> void:
	var rounded := profile == Profile.ROUNDED
	var extent := ceili(length * 0.6 + width * 0.6)
	var left := int(center.x) - extent if rounded else int(center.x - length)
	var right := int(center.x) + extent + 1 if rounded else int(center.x + length + 1)
	var top := int(center.y) - extent if rounded else int(center.y - length)
	var bottom := int(center.y) + extent + 1 if rounded else int(center.y + length + 1)
	var axis := Vector2(cos(angle), sin(angle))
	var side := Vector2(-axis.y, axis.x)
	for y in range(maxi(0, top), mini(image.get_height(), bottom)):
		for x in range(maxi(0, left), mini(image.get_width(), right)):
			var delta := Vector2(x, y) - center
			if rounded:
				var point := delta.rotated(-angle)
				var v := point.y / (length * 0.5)
				if absf(v) >= 1:
					continue
				var half_width := width * 0.5 * pow(1 - v * v, 0.8)
				if absf(point.x) > half_width:
					continue
				var ink: float = shade - (0.27 if outline and absf(point.x) > half_width - 0.9 else 0)
				image.set_pixel(x, y, Color(ink, ink, ink, 1))
			else:
				var u := delta.dot(axis) / length
				var v := delta.dot(side) / width
				var edge := u * u + v * v * (1.0 + absf(u) * 0.7)
				if edge > 1:
					continue
				var tint := shade * (0.88 + 0.12 * (1.0 - v))
				if edge > 0.78:
					tint *= 0.72
				if absf(v) < 0.055:
					tint *= 0.73
				image.set_pixel(x, y, Color(tint * 0.94, tint, tint * 0.85, clampf((1 - edge) * 8, 0, 1)))
