extends RefCounted
## Seeded brush marks: every leaf spray is painted into a runtime image.
static func leaf_spray() -> Texture2D:
	var image=Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var rng=RandomNumberGenerator.new();rng.seed=73421
	for layer in range(2):
		for i in range(64):
			var angle=rng.randf()*TAU
			var radius=sqrt(rng.randf())*87
			var center=Vector2(128,128)+Vector2(cos(angle),sin(angle)*.82)*radius
			var length=rng.randf_range(9,21)
			var width=length*rng.randf_range(.28,.56)
			var turn=angle+rng.randf_range(-1.2,1.2)
			var axis=Vector2(cos(turn),sin(turn));var side=Vector2(-axis.y,axis.x)
			var shade=rng.randf_range(.46,.72) if layer==0 else rng.randf_range(.7,1.0)
			for y in range(maxi(0,int(center.y-length)),mini(256,int(center.y+length+1))):
				for x in range(maxi(0,int(center.x-length)),mini(256,int(center.x+length+1))):
					var delta=Vector2(x,y)-center
					var u=delta.dot(axis)/length;var v=delta.dot(side)/width
					var edge=u*u+v*v*(1.+absf(u)*.7)
					if edge>1:continue
					var tint=shade*(.88+.12*(1.-v))
					if edge>.78:tint*=.72
					if absf(v)<.055:tint*=.73
					image.set_pixel(x,y,Color(tint*.94,tint,tint*.85,clampf((1-edge)*8,0,1)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
