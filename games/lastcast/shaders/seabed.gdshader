shader_type spatial;
// Procedural submerged stone, sand pockets and eelgrass: no imported textures.
uniform vec4 sand : source_color = vec4(.44, .55, .43, 1.0);
uniform vec4 depths : source_color = vec4(.035, .21, .27, 1.0);
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world.xz;
	float depth = max(0.0, -world.y);
	float patch = noise(p * .65) * .7 + noise(p * 1.3) * .3;
	float grain = noise(p * 8.0);
	float stones = smoothstep(.42, .69, noise(p * 3.8 + vec2(noise(p * .8))));
	float grass = smoothstep(.57, .76, patch);
	vec3 base = sand.rgb * (.84 + stones * .14 + grain * .035);
	base = mix(base, vec3(.12, .27, .20), grass * .25);
	// Fine broken light filaments, formed by intersecting unrelated noise fields.
	// A slow patch mask breaks the contours before they become a white lattice.
	vec2 flow = vec2(TIME * .085, -TIME * .065);
	vec2 drift = vec2(noise(p * .9 + flow), noise(p * 1.1 - flow));
	vec2 q = p * 2.8 + drift * .75;
	vec2 cross_q = vec2(q.x * .80 + q.y * .60, q.x * -.60 + q.y * .80);
	float crossing = abs(noise(q + flow) - noise(cross_q * 1.17 - flow));
	float filament = 1.0 - smoothstep(.025, .105, crossing);
	float broken = smoothstep(.40, .72, noise(p * 1.35 + flow * .45));
	float nearby = 1.0 - smoothstep(25.0, 70.0, length(world - CAMERA_POSITION_WORLD));
	float caustic = filament * broken * nearby;
	base += vec3(.11, .15, .085) * caustic * exp(-depth * .27);
	base = mix(base, depths.rgb, 1.0 - exp(-depth * .16));
	ALBEDO = pow(base, vec3(2.2));
	ROUGHNESS = .96;
	SPECULAR = .05;
}
