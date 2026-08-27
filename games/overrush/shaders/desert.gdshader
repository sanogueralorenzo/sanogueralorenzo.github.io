shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 seed_offset = vec2(0.0);
uniform vec2 world_origin = vec2(0.0);

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), local.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), local.x),
		local.y
	);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = world_position.xz + world_origin + seed_offset;
	float broad = noise(p * 0.0035);
	float ripples = noise(p * 0.035 + vec2(31.0, -17.0));
	float wind_lines = sin((p.x * 0.13 + p.y * 0.035) + ripples * 2.4) * 0.5 + 0.5;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float stone = smoothstep(0.34, 0.67, slope + (broad - 0.5) * 0.16);
	vec3 pale_sand = vec3(0.79, 0.43, 0.15);
	vec3 sunlit_sand = vec3(1.0, 0.73, 0.31);
	vec3 sand = mix(pale_sand, sunlit_sand, broad * 0.72 + wind_lines * 0.28);
	vec3 rock = mix(vec3(0.16, 0.075, 0.055), vec3(0.43, 0.19, 0.09), broad);
	ALBEDO = mix(sand, rock, stone);
	ROUGHNESS = mix(0.96, 0.78, stone);
	SPECULAR = 0.12;
}
