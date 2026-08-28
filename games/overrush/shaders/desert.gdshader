shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 seed_offset = vec2(0.0);
uniform vec2 world_origin = vec2(0.0);
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float surface_texture_scale = 0.025;
uniform vec3 shadow_sand : source_color = vec3(0.12, 0.075, 0.045);
uniform vec3 pale_sand : source_color = vec3(0.43, 0.25, 0.105);
uniform vec3 sunlit_sand : source_color = vec3(0.68, 0.42, 0.18);
uniform vec3 sandstone : source_color = vec3(0.25, 0.16, 0.12);
uniform vec3 shadow_grass : source_color = vec3(0.042, 0.085, 0.052);
uniform vec3 grass : source_color = vec3(0.085, 0.205, 0.1);
uniform vec3 sunlit_grass : source_color = vec3(0.21, 0.36, 0.15);

varying vec3 world_position;
varying vec3 world_normal;
varying float grass_weight;

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
	grass_weight = COLOR.r;
}

void fragment() {
	vec2 p = world_position.xz + world_origin + seed_offset;
	vec2 surface_uv = p * surface_texture_scale;
	mat2 detail_rotation = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	vec2 detail_uv = detail_rotation * surface_uv * 0.57 + vec2(13.1, -7.4);
	vec3 sand_texel = mix(texture(sand_albedo, surface_uv).rgb, texture(sand_albedo, detail_uv).rgb, 0.28);
	vec3 grass_texel = mix(texture(grass_albedo, surface_uv).rgb, texture(grass_albedo, detail_uv).rgb, 0.28);
	float broad = noise(p * 0.0035);
	float ripples = noise(p * 0.044 + vec2(31.0, -17.0));
	float grass_mottle = noise(p * 0.012 + vec2(-53.0, 29.0));
	float wind_lines = sin((p.x * 0.16 + p.y * 0.044) + ripples * 2.8) * 0.5 + 0.5;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float stone = smoothstep(0.34, 0.67, slope + (broad - 0.5) * 0.16);
	vec3 key_light_direction = normalize(vec3(-0.35, 0.74, 0.57));
	float key_light = smoothstep(0.42, 0.88, max(dot(world_normal, key_light_direction), 0.0));
	float wind_crest = smoothstep(0.76, 0.98, wind_lines) * (1.0 - smoothstep(0.22, 0.52, slope));
	vec3 sand_surface = mix(pale_sand, sunlit_sand, broad * 0.68 + wind_lines * 0.18 + 0.08);
	sand_surface = mix(shadow_sand, sand_surface, 0.28 + key_light * 0.72);
	sand_surface = mix(sand_surface, sand_texel, 0.22);
	sand_surface += wind_crest * vec3(0.07, 0.035, 0.01);
	vec3 grass_surface = mix(grass, sunlit_grass, broad * 0.58 + ripples * 0.2 + 0.12);
	grass_surface = mix(shadow_grass, grass_surface, 0.3 + key_light * 0.7);
	grass_surface = mix(grass_surface, grass_texel, 0.22);
	grass_surface *= mix(vec3(0.82, 0.9, 0.85), vec3(1.02, 1.0, 0.82), grass_mottle);
	float biome_blend = smoothstep(0.08, 0.92, grass_weight);
	vec3 rideable_surface = mix(sand_surface, grass_surface, biome_blend);
	vec3 rock = mix(shadow_sand * 0.62, sandstone, broad);
	ALBEDO = mix(rideable_surface, rock, stone);
	float surface_luma = mix(dot(sand_texel, vec3(0.299, 0.587, 0.114)), dot(grass_texel, vec3(0.299, 0.587, 0.114)), biome_blend);
	ROUGHNESS = mix(mix(0.88 + surface_luma * 0.08 - wind_crest * 0.1, 0.97, biome_blend), 0.82, stone);
	SPECULAR = mix(0.18, 0.08, stone);
}
